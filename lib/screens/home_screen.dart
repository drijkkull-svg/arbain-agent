import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../services/device_admin_service.dart';
import '../services/schedule_service.dart';
import '../services/auto_update_service.dart';
import '../services/geofence_service.dart';
import 'login_screen.dart';
import 'pairing_screen.dart';
import 'apps_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _deviceAdmin = DeviceAdminService();
  final _scheduleService = ScheduleService();
  final _autoUpdate = AutoUpdateService();
  final _geofenceService = GeofenceService();

  String _status = 'Memulai...';
  bool _isTracking = false;
  bool _isRestricted = false;
  bool _isSleep = false;
  bool _isAlarmActive = false;
  bool _isLostMode = false;
  bool _isAdminActive = false;
  String _santriName = '';
  String _kamar = '';
  String _lastSync = '-';
  DateTime _now = DateTime.now();
  Timer? _clockTimer;
  List<Map<String, dynamic>> _todaySchedules = [];
  Map<String, int> _appUsageMinutes = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTracking();
    _listenToDeviceCommands();
    _loadTodaySchedules();
    _loadAppUsage();
    SharedPreferences.getInstance().then((prefs) => setState(() {
          _isSleep = prefs.getBool('is_sleep') ?? false;
          _isRestricted = prefs.getBool('is_restricted') ?? false;
          _santriName = prefs.getString('username') ?? '';
          _kamar = prefs.getString('kamar') ?? '';
        }));
    _deviceAdmin.listenLockCommand();
    _checkAdminStatus();
    _scheduleService.startScheduleChecker((shouldRestrict) {
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setBool('is_restricted', shouldRestrict));
    });
    _checkUsageAccess();
    _geofenceService.startGeofenceChecker();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _autoUpdate.checkUpdate(context));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isRestricted) _enterKioskMode();
    });
    // Clock timer
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _geofenceService.stop();
    _scheduleService.stop();
    super.dispose();
  }

  Future<void> _loadTodaySchedules() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      final snap = await _firestore.collection('schedules').get();
      final days = ['Minggu','Senin','Selasa','Rabu','Kamis','Jumat','Sabtu'];
      final today = days[DateTime.now().weekday % 7];
      final result = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final isActive = data['isActive'] ?? false;
        if (!isActive) continue;
        final daysList = List<String>.from(data['days'] ?? []);
        if (!daysList.contains(today)) continue;
        result.add({
          'type': data['type'] ?? 'sleep',
          'startTime': data['startTime'] ?? '',
          'endTime': data['endTime'] ?? '',
        });
      }
      if (mounted) setState(() => _todaySchedules = result);
    } catch (e) {
      debugPrint('loadTodaySchedules error: $e');
    }
  }

  Future<void> _loadAppUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('flutter.app_usage_today') ?? '';
      if (raw.isEmpty) return;
      final json = raw.replaceAll('{', '').replaceAll('}', '');
      final map = <String, int>{};
      for (final entry in json.split(',')) {
        final parts = entry.split(':');
        if (parts.length == 2) {
          final pkg = parts[0].trim().replaceAll('"', '');
          final ms = int.tryParse(parts[1].trim()) ?? 0;
          if (ms > 0) map[pkg] = ms ~/ 60000;
        }
      }
      final sorted = Map.fromEntries(map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
      if (mounted) setState(() => _appUsageMinutes = Map.fromEntries(sorted.entries.take(5)));
    } catch (e) {
      debugPrint('loadAppUsage error: $e');
    }
  }

  Future<void> _enterKioskMode() async {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky, overlays: []);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    try {
      await const MethodChannel('com.example.arbain_agent/device_admin').invokeMethod('startLockTask');
    } catch (e) { debugPrint('startLockTask error: $e'); }
  }

  Future<void> _exitKioskMode() async {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    try {
      await const MethodChannel('com.example.arbain_agent/device_admin').invokeMethod('stopLockTask');
    } catch (e) { debugPrint('stopLockTask error: $e'); }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && _isRestricted) {
      Future.delayed(const Duration(milliseconds: 800), () { _enterKioskMode(); });
    }
    if (state == AppLifecycleState.resumed) _loadAppUsage();
  }

  Future<void> _checkUsageAccess() async {}

  Future<void> _checkAdminStatus() async {
    final active = await _deviceAdmin.isAdminActive();
    setState(() { _isAdminActive = active; });
  }

  void _listenToDeviceCommands() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    SharedPreferences.getInstance().then((prefs) => prefs.setString('device_uid', uid));
    _firestore.collection('devices').doc(uid).snapshots().listen((snap) async {
      if (!snap.exists) return;
      final data = snap.data()!;
      _saveRestrictedState(data['isRestricted'] ?? false);
      final prefs2 = await SharedPreferences.getInstance();
      if (!mounted) return;
      final wasRestricted = _isRestricted;
      final nowRestricted = data['isRestricted'] ?? false;
      setState(() {
        _isRestricted = nowRestricted;
        _isSleep = prefs2.getBool('is_sleep') ?? false;
        _isAlarmActive = data['isAlarmActive'] ?? false;
        _isLostMode = data['isLostMode'] ?? false;
        _santriName = prefs2.getString('username') ?? '';
        _kamar = prefs2.getString('kamar') ?? '';
      });
      if (nowRestricted && !wasRestricted) _enterKioskMode();
      else if (!nowRestricted && wasRestricted) _exitKioskMode();
    });
  }

  Future<void> _startTracking() async {
    setState(() { _status = 'Mengirim lokasi...'; _isTracking = true; });
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        setState(() { _status = 'Izin lokasi ditolak.'; });
        return;
      }
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        await _firestore.collection('devices').doc(uid).update({
          'location': {'lat': position.latitude, 'lng': position.longitude},
          'isOnline': true,
          'updatedAt': DateTime.now().toIso8601String(),
        });
        final now = DateTime.now();
        setState(() {
          _status = 'Lokasi terkirim!';
          _lastSync = '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';
        });
      }
    } catch (e) { setState(() { _status = 'Error: $e'; }); }
  }

  Future<void> _saveRestrictedState(bool isRestricted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_restricted', isRestricted);
  }

  String _generateCode() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now % 900000 + 100000).toString();
  }

  Future<void> _requestLogout() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final code = _generateCode();
    await _firestore.collection('logout_requests').doc(uid).set({
      'santriId': uid, 'code': code, 'status': 'pending',
      'requestedAt': DateTime.now().toIso8601String(),
    });
    await _firestore.collection('notifications_admin').add({
      'type': 'logout_request', 'santriId': uid, 'code': code,
      'message': 'Santri meminta izin logout. Kode akses: $code',
      'isRead': false, 'timestamp': DateTime.now().toIso8601String(),
    });
    if (!mounted) return;
    final codeController = TextEditingController();
    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Izin Logout', style: TextStyle(color: Color(0xFF00FF88))),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Permintaan logout telah dikirim ke pengurus.\nMasukkan kode akses yang diberikan pengurus:', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 16),
          TextField(
            controller: codeController, keyboardType: TextInputType.number, maxLength: 6,
            style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              counterText: '', hintText: '______', hintStyle: const TextStyle(color: Colors.white24),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: const Color(0xFF00FF88).withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF00FF88)), borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () async { await _firestore.collection('logout_requests').doc(uid).delete(); if (ctx.mounted) Navigator.pop(ctx); }, child: const Text('Batal', style: TextStyle(color: Colors.red))),
          ElevatedButton(
            onPressed: () async {
              if (codeController.text.trim() == code) {
                await _firestore.collection('logout_requests').doc(uid).delete();
                if (ctx.mounted) Navigator.pop(ctx);
                await _logout();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kode salah!'), backgroundColor: Colors.red));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF88), foregroundColor: Colors.black),
            child: const Text('Konfirmasi'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await _firestore.collection('devices').doc(_auth.currentUser?.uid).update({'isOnline': false});
    await _auth.signOut();
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  String _formatHari(DateTime dt) {
    const hari = ['Minggu','Senin','Selasa','Rabu','Kamis','Jumat','Sabtu'];
    return hari[dt.weekday % 7];
  }

  String _formatTanggal(DateTime dt) {
    const bulan = ['','Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agt','Sep','Okt','Nov','Des'];
    return '${_formatHari(dt)}, ${dt.day} ${bulan[dt.month]} ${dt.year}';
  }

  String _appLabel(String pkg) {
    const map = {
      'com.instagram.android': 'Instagram',
      'com.zhiliaoapp.musically': 'TikTok',
      'com.ss.android.ugc.trill': 'TikTok',
      'com.whatsapp': 'WhatsApp',
      'com.facebook.katana': 'Facebook',
      'com.google.android.youtube': 'YouTube',
      'com.android.chrome': 'Chrome',
      'com.lemon.lvoverseas': 'CapCut',
      'com.twitter.android': 'Twitter/X',
      'com.snapchat.android': 'Snapchat',
    };
    return map[pkg] ?? pkg.split('.').last;
  }

  @override
  Widget build(BuildContext context) {
    if (_isRestricted) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) { _enterKioskMode(); },
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
          child: Scaffold(
            backgroundColor: const Color(0xFF0A0A0A),
            body: GestureDetector(
              onVerticalDragStart: (_) {}, onHorizontalDragStart: (_) {},
              child: Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('PONDOK PESANTREN', style: TextStyle(color: Color(0xFF00FF88), fontSize: 14, letterSpacing: 2)),
                  const Text("Al-Mubarok Al-Arba'in", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  const Icon(Icons.lock, color: Colors.red, size: 80),
                  const SizedBox(height: 24),
                  Text(_isSleep ? 'WAKTU ISTIRAHAT' : 'PERANGKAT DIBATASI', style: TextStyle(color: _isSleep ? Colors.blue : Colors.red, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text('Hubungi pengurus pondok untuk membuka akses.', style: TextStyle(color: Colors.white54), textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(icon: const Icon(Icons.phone, color: Color(0xFF00FF88), size: 40), onPressed: () => launchUrl(Uri.parse('tel:'))),
                    const SizedBox(width: 40),
                    IconButton(icon: const Icon(Icons.camera_alt, color: Color(0xFF00FF88), size: 40), onPressed: () => launchUrl(Uri.parse('market://launch?id=com.android.camera2'))),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    if (_isLostMode) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.warning, color: Colors.orange, size: 80),
              const SizedBox(height: 24),
              const Text('MODE HILANG AKTIF', style: TextStyle(color: Colors.orange, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text("HP ini milik Pondok Al-Arba'in, harap hubungi pengurus segera.", style: TextStyle(color: Colors.white54), textAlign: TextAlign.center),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        title: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: const Color(0xFF00FF88).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.shield, color: Color(0xFF00FF88), size: 20),
          ),
          const SizedBox(width: 10),
          const Text('Arbain Agent', style: TextStyle(color: Color(0xFF00FF88), fontWeight: FontWeight.bold, fontSize: 18)),
        ]),
        actions: [
          if (_isAlarmActive) const Icon(Icons.notifications_active, color: Colors.red),
          IconButton(icon: const Icon(Icons.logout, color: Colors.white54), onPressed: _requestLogout),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // JAM & TANGGAL
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF003322), Color(0xFF001a11)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF00FF88).withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${_now.hour.toString().padLeft(2,'0')}:${_now.minute.toString().padLeft(2,'0')}:${_now.second.toString().padLeft(2,'0')}',
                  style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 2),
                ),
                Text(_formatTanggal(_now), style: const TextStyle(color: Color(0xFF00FF88), fontSize: 13)),
              ]),
              const Spacer(),
              if (_santriName.isNotEmpty) Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_santriName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                if (_kamar.isNotEmpty) Text('Kamar $_kamar', style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
            ]),
          ),

          // STATUS PERANGKAT
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF00FF88).withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('STATUS PERANGKAT', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.5)),
              const SizedBox(height: 12),
              Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: _isTracking ? const Color(0xFF00FF88) : Colors.red, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(_status, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('Sync: $_lastSync', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.admin_panel_settings, color: _isAdminActive ? const Color(0xFF00FF88) : Colors.red, size: 16),
                const SizedBox(width: 8),
                Text(_isAdminActive ? 'Device Admin Aktif' : 'Device Admin Tidak Aktif',
                    style: TextStyle(color: _isAdminActive ? const Color(0xFF00FF88) : Colors.red, fontSize: 13)),
              ]),
            ]),
          ),

          // JADWAL HARI INI
          if (_todaySchedules.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('JADWAL HARI INI', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.5)),
                const SizedBox(height: 12),
                ..._todaySchedules.map((s) {
                  final isSleep = s['type'] == 'sleep';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Icon(isSleep ? Icons.bedtime : Icons.menu_book, color: isSleep ? Colors.blue : Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Text(isSleep ? 'Jam Tidur' : 'Mode Ngaji', style: TextStyle(color: isSleep ? Colors.blue : Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('${s['startTime']} - ${s['endTime']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ]),
                  );
                }),
              ]),
            ),
          ],

          // MENU GRID
          const Text('MENU', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.5)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.3,
            children: [
              _menuCard(Icons.sync, 'Sinkronisasi', 'Perbarui data app', const Color(0xFF00FF88), () async {
                setState(() => _status = 'Menyinkronkan...');
                await _startTracking();
                await _loadTodaySchedules();
                await _loadAppUsage();
              }),
              _menuCard(Icons.link, 'Hubungkan\nPerangkat', 'Pairing dengan pengurus', const Color(0xFF00AAFF), () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PairingScreen()));
              }),
              _menuCard(Icons.apps, 'Aplikasi', 'Lihat app terinstall', const Color(0xFFFF9900), () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AppsScreen()));
              }),
              _menuCard(Icons.location_on, 'Lokasi', 'Kirim lokasi sekarang', const Color(0xFFFF4466), () async {
                setState(() => _status = 'Mengirim lokasi...');
                await _startTracking();
              }),
            ],
          ),

          const SizedBox(height: 16),

          // STATISTIK PEMAKAIAN APP
          if (_appUsageMinutes.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('PEMAKAIAN APP HARI INI', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.5)),
                  const Spacer(),
                  const Icon(Icons.bar_chart, color: Colors.purple, size: 16),
                ]),
                const SizedBox(height: 12),
                ..._appUsageMinutes.entries.map((e) {
                  final maxMin = _appUsageMinutes.values.first;
                  final pct = maxMin > 0 ? e.value / maxMin : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(_appLabel(e.key), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        const Spacer(),
                        Text('${e.value} menit', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ]),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct, minHeight: 6,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.purple),
                        ),
                      ),
                    ]),
                  );
                }),
              ]),
            ),
          ],

          // INFO PONDOK
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF0D0D0D), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white12)),
            child: const Row(children: [
              Icon(Icons.info_outline, color: Colors.white24, size: 18),
              SizedBox(width: 10),
              Expanded(child: Text('Perangkat ini dikelola oleh Pengurus Pondok Pesantren Al-Mubarok Al-Arba\'in', style: TextStyle(color: Colors.white38, fontSize: 12))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _menuCard(IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 22),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ]),
        ]),
      ),
    );
  }
}
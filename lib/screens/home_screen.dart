import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'dart:async';
import '../services/device_admin_service.dart';
import '../services/schedule_service.dart';
import '../services/auto_update_service.dart';
import '../services/app_usage_service.dart';
import '../services/geofence_service.dart';
import 'login_screen.dart';
import 'pairing_screen.dart';
import 'apps_screen.dart';
import 'profile_screen.dart';
import 'attendance_screen.dart';

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
  final _battery = Battery();

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
  Timer? _batteryTimer;
  List<Map<String, dynamic>> _todaySchedules = [];
  Map<String, int> _appUsageMinutes = {};
  int _batteryLevel = 0;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTracking();
    _listenToDeviceCommands();
    _listenToNotifications();
    _loadTodaySchedules();
    _loadAppUsage();
    _loadBattery();
    AppUsageService.syncAppUsage();
    Timer.periodic(const Duration(minutes: 30), (_) => AppUsageService.syncAppUsage());
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
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _batteryTimer = Timer.periodic(const Duration(minutes: 2), (_) => _loadBattery());
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _batteryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _geofenceService.stop();
    _scheduleService.stop();
    super.dispose();
  }

  Future<void> _loadBattery() async {
    try {
      final level = await _battery.batteryLevel;
      if (mounted) {
        setState(() => _batteryLevel = level);
        final uid = _auth.currentUser?.uid;
        if (uid != null) {
          await _firestore.collection('devices').doc(uid).update({'batteryLevel': level});
        }
      }
    } catch (e) { debugPrint('battery error: $e'); }
  }

  void _listenToNotifications() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _firestore.collection('notifications')
        .where('targetAll', isEqualTo: true)
        .limit(20)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final now = DateTime.now();
      final list = snap.docs
        .map((d) => {'id': d.id, ...d.data()})
        .where((n) {
          try {
            final created = DateTime.parse(n['createdAt'].toString());
            return now.difference(created).inHours < 24;
          } catch (_) { return true; }
        })
        .toList();
      setState(() => _notifications = list);
    });
  }

  Future<void> _loadTodaySchedules() async {
    try {
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
    } catch (e) { debugPrint('loadTodaySchedules error: $e'); }
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
    } catch (e) { debugPrint('loadAppUsage error: $e'); }
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
      // Alarm
      final wasAlarm = _isAlarmActive;
      final nowAlarm = data['isAlarmActive'] ?? false;
      final wasLost = _isLostMode;
      final nowLost = data['isLostMode'] ?? false;
      setState(() {
        _isAlarmActive = nowAlarm;
        _isLostMode = nowLost;
      });
      if (nowAlarm && !wasAlarm) {
        try {
          await const MethodChannel('com.example.arbain_agent/device_admin').invokeMethod('playAlarm');
        } catch (e) { debugPrint('alarm error: $e'); }
      } else if (!nowAlarm && wasAlarm) {
        try {
          await const MethodChannel('com.example.arbain_agent/device_admin').invokeMethod('stopAlarm');
        } catch (e) { debugPrint('stop alarm error: $e'); }
      }
      if (nowLost && !wasLost) {
        try { await _deviceAdmin.lockScreen(); } catch (e) {}
      }
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
          _status = 'Lokasi terkirim';
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
        title: const Text('Izin Logout', style: TextStyle(color: Color(0xFF4ade80))),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Permintaan logout telah dikirim ke pengurus.\nMasukkan kode akses yang diberikan pengurus:', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 16),
          TextField(
            controller: codeController, keyboardType: TextInputType.number, maxLength: 6,
            style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              counterText: '', hintText: '______', hintStyle: const TextStyle(color: Colors.white24),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: const Color(0xFF4ade80).withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF4ade80)), borderRadius: BorderRadius.circular(8)),
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4ade80), foregroundColor: Colors.black),
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

  Color _batteryColor() {
    if (_batteryLevel > 50) return const Color(0xFF4ade80);
    if (_batteryLevel > 20) return Colors.orange;
    return Colors.red;
  }

  IconData _batteryIcon() {
    if (_batteryLevel > 80) return Icons.battery_full;
    if (_batteryLevel > 50) return Icons.battery_5_bar;
    if (_batteryLevel > 20) return Icons.battery_3_bar;
    return Icons.battery_1_bar;
  }

  static const _bg = Color(0xFF070f07);
  static const _green = Color(0xFF4ade80);
  static const _card = Color(0xFF0d0d0d);
  static const _cardBorder = Color(0xFF1a1a1a);

  @override
  Widget build(BuildContext context) {
    if (_isRestricted) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) { _enterKioskMode(); },
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
          child: Scaffold(
            backgroundColor: _bg,
            body: GestureDetector(
              onVerticalDragStart: (_) {}, onHorizontalDragStart: (_) {},
              child: Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('PONDOK PESANTREN', style: TextStyle(color: _green, fontSize: 14, letterSpacing: 2)),
                  const Text("Al-Mubarok Al-Arba'in", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  const Icon(Icons.lock, color: Colors.red, size: 80),
                  const SizedBox(height: 24),
                  Text(_isSleep ? 'WAKTU ISTIRAHAT' : 'PERANGKAT DIBATASI', style: TextStyle(color: _isSleep ? Colors.blue : Colors.red, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text('Hubungi pengurus pondok untuk membuka akses.', style: TextStyle(color: Colors.white54), textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(icon: const Icon(Icons.phone, color: _green, size: 40), onPressed: () => launchUrl(Uri.parse('tel:'))),
                    const SizedBox(width: 40),
                    IconButton(icon: const Icon(Icons.camera_alt, color: _green, size: 40), onPressed: () => launchUrl(Uri.parse('market://launch?id=com.android.camera2'))),
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
          backgroundColor: _bg,
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light),
      child: Scaffold(
        backgroundColor: _bg,
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.8, -1.0),
              radius: 1.2,
              colors: [Color(0xFF0a2e12), _bg],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // TOP BAR
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: const Color(0xFF16a34a), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.shield, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Text('Arbain Agent', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (_isAlarmActive)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        child: const Icon(Icons.notifications_active, color: Colors.red, size: 22),
                      ),
                    // NOTIF BELL
                    GestureDetector(
                      onTap: _showNotifications,
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: _notifications.isNotEmpty ? const Color(0xFF0a1f0a) : const Color(0xFF0f0f0f),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _notifications.isNotEmpty ? const Color(0xFF1a5e28) : const Color(0xFF1e1e1e)),
                        ),
                        child: Stack(alignment: Alignment.center, children: [
                          Icon(Icons.notifications_outlined, color: _notifications.isNotEmpty ? _green : Colors.white38, size: 20),
                          if (_notifications.any((n) => n['read'] != true))
                            Positioned(top: 6, right: 6, child: Container(
                              width: 7, height: 7,
                              decoration: BoxDecoration(color: _green, shape: BoxShape.circle, border: Border.all(color: _bg, width: 1.5)),
                            )),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // MORE OPTIONS
                    GestureDetector(
                      onTap: () => _showMoreOptions(),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: const Color(0xFF0f0f0f), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF1e1e1e))),
                        child: const Icon(Icons.more_horiz, color: Colors.white38, size: 20),
                      ),
                    ),
                  ]),
                ),

                // HERO — JAM + STATUS
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(width: 7, height: 7, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('Online • $_santriName', style: const TextStyle(color: _green, fontSize: 12, fontWeight: FontWeight.w500)),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      '${_now.hour.toString().padLeft(2,'0')}:${_now.minute.toString().padLeft(2,'0')}',
                      style: const TextStyle(color: Colors.white, fontSize: 58, fontWeight: FontWeight.w700, letterSpacing: -2, height: 1),
                    ),
                    Text(_formatTanggal(_now), style: const TextStyle(color: Color(0xFF4a6e50), fontSize: 13)),
                    const SizedBox(height: 14),
                    // BADGES
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _badge(Icons.location_on, 'Lokasi aktif', const Color(0xFF0a2e14), const Color(0xFF1a5e28), _green),
                      _badge(_batteryIcon(), '$_batteryLevel%', const Color(0xFF111), const Color(0xFF222), Colors.white54),
                      _badge(Icons.admin_panel_settings, _isAdminActive ? 'Admin aktif' : 'Admin nonaktif',
                        _isAdminActive ? const Color(0xFF0a1a0a) : const Color(0xFF1a0a0a),
                        _isAdminActive ? const Color(0xFF1a3a1a) : const Color(0xFF3a1a1a),
                        _isAdminActive ? _green : Colors.red),
                    ]),
                    const SizedBox(height: 14),
                    // SYNC CARD
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0d0d0d).withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF1a3a22)),
                      ),
                      child: Row(children: [
                        Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(color: const Color(0xFF0f2d1a), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.check_circle_outline, color: _green, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_status, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                          Text('Sync $_lastSync${_kamar.isNotEmpty ? ' • Kamar $_kamar' : ''}', style: const TextStyle(color: Color(0xFF3d6b4a), fontSize: 11)),
                        ]),
                        const Spacer(),
                        GestureDetector(
                          onTap: () async {
                            setState(() => _status = 'Menyinkronkan...');
                            await _startTracking();
                            await _loadTodaySchedules();
                            await _loadAppUsage();
                            await _loadBattery();
                          },
                          child: const Icon(Icons.refresh, color: Color(0xFF2d5a3a), size: 20),
                        ),
                      ]),
                    ),
                  ]),
                ),

                const SizedBox(height: 18),

                // PENGUMUMAN
                if (_notifications.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1a1200),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF3a2800)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Icon(Icons.campaign, color: Colors.amber, size: 15),
                          const SizedBox(width: 6),
                          const Text('PENGUMUMAN', style: TextStyle(color: Colors.amber, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          Text('${_notifications.length} baru', style: const TextStyle(color: Color(0xFF7a6000), fontSize: 10)),
                        ]),
                        const SizedBox(height: 10),
                        ...(_notifications.take(2).map((n) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Padding(padding: EdgeInsets.only(top: 5), child: Icon(Icons.circle, color: Colors.amber, size: 5)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(n['message'] ?? '', style: const TextStyle(color: Colors.white60, fontSize: 12))),
                          ]),
                        ))),
                      ]),
                    ),
                  ),

                // JADWAL HARI INI
                if (_todaySchedules.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF08101a),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF102030)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Row(children: [
                          Icon(Icons.calendar_today, color: Color(0xFF60a5fa), size: 15),
                          SizedBox(width: 6),
                          Text('JADWAL HARI INI', style: TextStyle(color: Color(0xFF60a5fa), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 10),
                        ..._todaySchedules.map((s) {
                          final isSleep = s['type'] == 'sleep';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(children: [
                              Icon(isSleep ? Icons.bedtime : Icons.menu_book, color: isSleep ? const Color(0xFF60a5fa) : Colors.orange, size: 16),
                              const SizedBox(width: 8),
                              Text(isSleep ? 'Jam Tidur' : 'Mode Ngaji', style: TextStyle(color: isSleep ? const Color(0xFF60a5fa) : Colors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
                              const Spacer(),
                              Text('${s['startTime']} - ${s['endTime']}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            ]),
                          );
                        }),
                      ]),
                    ),
                  ),

                // MENU LABEL
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: Text('MENU', style: TextStyle(color: Color(0xFF2a4a2a), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
                ),

                // MENU GRID
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: GridView.count(
                    crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.1,
                    children: [
                      _menuCard(Icons.qr_code_scanner, 'Absen', 'Scan QR sekarang', const Color(0xFF4ade80), const Color(0xFF071f0f), const Color(0xFF1a4a22), () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceScreen()));
                      }),
                      _menuCard(Icons.refresh, 'Sinkronisasi', 'Perbarui data', const Color(0xFF4a6e50), _card, _cardBorder, () async {
                        setState(() => _status = 'Menyinkronkan...');
                        await _startTracking();
                        await _loadTodaySchedules();
                        await _loadAppUsage();
                        await _loadBattery();
                      }),
                      _menuCard(Icons.notifications_outlined, 'Notifikasi', '${_notifications.length} belum dibaca', const Color(0xFFfbbf24), const Color(0xFF1a0f00), const Color(0xFF3a2000), _showNotifications),
                      _menuCard(Icons.location_on_outlined, 'Lokasi', 'Kirim sekarang', const Color(0xFFf87171), const Color(0xFF1a0808), const Color(0xFF3a1010), () async {
                        setState(() => _status = 'Mengirim lokasi...');
                        await _startTracking();
                      }),
                      _menuCard(Icons.person_outline, 'Profil', 'Lihat & edit', const Color(0xFFc084fc), const Color(0xFF100818), const Color(0xFF280a3a), () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                      }),
                      _menuCard(Icons.calendar_month_outlined, 'Absensi', 'Rekap kehadiran', const Color(0xFF60a5fa), const Color(0xFF08101a), const Color(0xFF102030), () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceScreen()));
                      }),
                      _menuCard(Icons.link, 'Hubungkan', 'Pairing pengurus', const Color(0xFF2dd4bf), const Color(0xFF041410), const Color(0xFF0a3028), () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const PairingScreen()));
                      }),
                      _menuCard(Icons.apps_outlined, 'Aplikasi', 'App terinstall', const Color(0xFF4a6e50), _card, _cardBorder, () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AppsScreen()));
                      }),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // PEMAKAIAN APP
                if (_appUsageMinutes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF100818),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF280a3a)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Row(children: [
                          Icon(Icons.bar_chart, color: Color(0xFFc084fc), size: 15),
                          SizedBox(width: 6),
                          Text('PEMAKAIAN APP HARI INI', style: TextStyle(color: Color(0xFFc084fc), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 12),
                        ..._appUsageMinutes.entries.map((e) {
                          final maxMin = _appUsageMinutes.values.first;
                          final pct = maxMin > 0 ? e.value / maxMin : 0.0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Text(_appLabel(e.key), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                                const Spacer(),
                                Text('${e.value} menit', style: const TextStyle(color: Colors.white30, fontSize: 11)),
                              ]),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: pct, minHeight: 4,
                                  backgroundColor: Colors.white10,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFc084fc)),
                                ),
                              ),
                            ]),
                          );
                        }),
                      ]),
                    ),
                  ),

                // INFO PONDOK
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFF0a0f0a), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF141e14))),
                    child: const Row(children: [
                      Icon(Icons.info_outline, color: Color(0xFF2a4a2a), size: 16),
                      SizedBox(width: 10),
                      Expanded(child: Text('Perangkat ini dikelola oleh Pengurus Pondok Pesantren Al-Mubarok Al-Arba\'in', style: TextStyle(color: Color(0xFF2a4a2a), fontSize: 11))),
                    ]),
                  ),
                ),

                // TOMBOL DARURAT
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                  child: GestureDetector(
                    onTap: () async {
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      if (uid == null) return;
                      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
                      final name = userDoc.data()?['name'] ?? 'Santri';
                      await FirebaseFirestore.instance.collection('panic_alerts').add({'santriId': uid, 'santriName': name, 'timestamp': DateTime.now().toIso8601String(), 'status': 'pending', 'isRead': false});
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Row(children: [Icon(Icons.sos, color: Colors.white), SizedBox(width: 8), Text('Bantuan darurat telah dikirim ke pengurus!')]), backgroundColor: Color(0xFFFF4444), duration: Duration(seconds: 3)));
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(color: const Color(0xFF1a0808), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF3a1010))),
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.sos, color: Color(0xFFf87171), size: 20),
                        SizedBox(width: 8),
                        Text('Kirim Bantuan Darurat', style: TextStyle(color: Color(0xFFf87171), fontSize: 14, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ),

              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(IconData icon, String label, Color bg, Color border, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99), border: Border.all(color: border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0f0f0f),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(99))),
          const SizedBox(height: 20),
          _optionTile(Icons.logout, 'Logout', Colors.red, () { Navigator.pop(ctx); _requestLogout(); }),
        ]),
      ),
    );
  }

  Widget _optionTile(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.2))),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  void _showNotifications() {
    setState(() => _notifications = _notifications.map((n) => {...n, 'read': true}).toList());
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0f0f0f),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(99))),
          const Text('PENGUMUMAN', style: TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          const SizedBox(height: 16),
          ..._notifications.map((n) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.campaign, color: Colors.amber, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n['message'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                if (n['createdAt'] != null)
                  Text(n['createdAt'].toString().substring(0, 10), style: const TextStyle(color: Colors.white30, fontSize: 11)),
              ])),
            ]),
          )),
        ]),
      ),
    );
  }

  Widget _menuCard(IconData icon, String title, String subtitle, Color color, Color bg, Color border, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22), border: Border.all(color: border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Icon(icon, color: color, size: 22),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(color: color.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.w500)),
          ]),
        ]),
      ),
    );
  }
}






import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../services/device_admin_service.dart';
import '../services/app_blocker_service.dart';
import '../services/auto_update_service.dart';
import 'login_screen.dart';
import 'pairing_screen.dart';
import 'apps_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _deviceAdmin = DeviceAdminService();
  final _appBlocker = AppBlockerService();
  bool _hasUsageAccess = false;
  final _autoUpdate = AutoUpdateService();
  String _status = 'Memulai...';
  bool _isTracking = false;
  bool _isRestricted = false;
  bool _isAlarmActive = false;
  bool _isLostMode = false;
  bool _isAdminActive = false;

  @override
  void initState() {
    super.initState();
    _startTracking();
    _listenToDeviceCommands();
    _checkAdminStatus();
    _deviceAdmin.listenLockCommand();
    _appBlocker.listenBlockedApps();
    _checkUsageAccess();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoUpdate.checkUpdate(context));
  }

  Future<void> _checkUsageAccess() async {
    final hasAccess = await _appBlocker.hasUsageAccess();
    setState(() { _hasUsageAccess = hasAccess; });
    if (!hasAccess) {
      await _appBlocker.openUsageAccessSettings();
    }
  }

  Future<void> _checkAdminStatus() async {
    final active = await _deviceAdmin.isAdminActive();
    setState(() { _isAdminActive = active; });
    if (!active) {
      await _deviceAdmin.requestAdminPermission();
      final activeAfter = await _deviceAdmin.isAdminActive();
      setState(() { _isAdminActive = activeAfter; });
    }
  }

  void _listenToDeviceCommands() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _firestore.collection('devices').doc(uid).snapshots().listen((snap) {
      if (!snap.exists) return;
      final data = snap.data()!;
      setState(() {
        _isRestricted = data['isRestricted'] ?? false;
        _isAlarmActive = data['isAlarmActive'] ?? false;
        _isLostMode = data['isLostMode'] ?? false;
      });
      if (data['isRestricted'] == true) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        _deviceAdmin.lockScreen();
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    });
  }

  Future<void> _startTracking() async {
    setState(() { _status = 'Mengirim lokasi...'; _isTracking = true; });
    try {
      LocationPermission permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() { _status = 'Izin lokasi ditolak.'; });
        return;
      }
      Position position = await Geolocator.getCurrentPosition();
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        await _firestore.collection('devices').doc(uid).update({
          'location': {'lat': position.latitude, 'lng': position.longitude},
          'isOnline': true,
          'updatedAt': DateTime.now().toIso8601String(),
        });
        setState(() { _status = 'Lokasi terkirim!'; });
      }
    } catch (e) {
      setState(() { _status = 'Error: $e'; });
    }
  }

  Future<void> _logout() async {
    await _firestore.collection('devices').doc(_auth.currentUser?.uid).update({'isOnline': false});
    await _auth.signOut();
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    if (_isRestricted) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock, color: Colors.red, size: 80),
                const SizedBox(height: 24),
                const Text('PERANGKAT DIBATASI', style: TextStyle(color: Colors.red, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text('Hubungi pengurus pondok untuk membuka akses.', style: TextStyle(color: Colors.white54), textAlign: TextAlign.center),
              ],
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning, color: Colors.orange, size: 80),
                const SizedBox(height: 24),
                const Text('MODE HILANG AKTIF', style: TextStyle(color: Colors.orange, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text("HP ini milik Pondok Al-Arba'in, harap hubungi pengurus segera.", style: TextStyle(color: Colors.white54), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text('Arbain Agent', style: TextStyle(color: Color(0xFF00FF88), fontWeight: FontWeight.bold)),
        actions: [
          if (_isAlarmActive) const Icon(Icons.notifications_active, color: Colors.red),
          IconButton(icon: const Icon(Icons.logout, color: Colors.white54), onPressed: _logout),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Status Perangkat', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(
                      color: _isTracking ? const Color(0xFF00FF88) : Colors.red,
                      shape: BoxShape.circle,
                    )),
                    const SizedBox(width: 8),
                    Text(_status, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.admin_panel_settings, color: _isAdminActive ? const Color(0xFF00FF88) : Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Text(_isAdminActive ? 'Device Admin Aktif' : 'Device Admin Tidak Aktif', style: TextStyle(color: _isAdminActive ? const Color(0xFF00FF88) : Colors.red, fontSize: 12)),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _startTracking,
                icon: const Icon(Icons.location_on),
                label: const Text('Perbarui Lokasi'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF88),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PairingScreen())),
                icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF00FF88)),
                label: const Text('Hubungkan Perangkat', style: TextStyle(color: Color(0xFF00FF88))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF00FF88)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppsScreen())),
                icon: const Icon(Icons.apps, color: Color(0xFF00FF88)),
                label: const Text('Sinkronisasi Aplikasi', style: TextStyle(color: Color(0xFF00FF88))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF00FF88)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}







import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/device_admin_service.dart';
import '../services/app_blocker_service.dart';
import 'home_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  static const _channel = MethodChannel('com.example.arbain_agent/permissions');
  final _deviceAdmin = DeviceAdminService();
  final _appBlocker = AppBlockerService();
  bool _adminOk = false;
  bool _overlayOk = false;
  bool _accessibilityOk = false;
  bool _usageOk = false;
  bool _batteryOk = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkAll();
  }

  Future<void> _checkAll() async {
    setState(() => _checking = true);
    final admin = await _deviceAdmin.isAdminActive();
    bool overlay = false;
    bool accessibility = false;
    bool battery = false;
    try {
      overlay = await _channel.invokeMethod('hasOverlayPermission') ?? false;
    } catch (_) { overlay = false; }
    try {
      accessibility = await _channel.invokeMethod('hasAccessibilityPermission') ?? false;
    } catch (_) { accessibility = false; }
    try {
      battery = await _channel.invokeMethod('hasBatteryOptimizationExemption') ?? false;
    } catch (_) { battery = false; }
    final usage = await _appBlocker.hasUsageAccess();
    setState(() {
      _adminOk = admin;
      _overlayOk = overlay;
      _accessibilityOk = accessibility;
      _usageOk = usage;
      _batteryOk = battery;
      _checking = false;
    });
  }

  bool get _allGranted => _adminOk && _overlayOk && _accessibilityOk && _usageOk && _batteryOk;

  Future<void> _requestAdmin() async {
    await _deviceAdmin.requestAdminPermission();
    await Future.delayed(const Duration(seconds: 1));
    await _checkAll();
  }

  Future<void> _requestOverlay() async {
    try { await _channel.invokeMethod('openOverlaySettings'); } catch (_) {}
    await Future.delayed(const Duration(seconds: 2));
    await _checkAll();
  }

  Future<void> _requestAccessibility() async {
    try { await _channel.invokeMethod('openAccessibilitySettings'); } catch (_) {}
    await Future.delayed(const Duration(seconds: 2));
    await _checkAll();
  }

  Future<void> _requestUsage() async {
    await _appBlocker.openUsageAccessSettings();
    await Future.delayed(const Duration(seconds: 2));
    await _checkAll();
  }

  Future<void> _requestBattery() async {
    try { await _channel.invokeMethod('openBatterySettings'); } catch (_) {}
    await Future.delayed(const Duration(seconds: 2));
    await _checkAll();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setup_done', true);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  Widget _buildItem({required String title, required String desc, required bool granted, required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: granted ? const Color(0xFF00FF88) : Colors.red.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(granted ? Icons.check_circle : Icons.error_outline, color: granted ? const Color(0xFF00FF88) : Colors.red, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ]),
          ),
          if (!granted)
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('Izinkan', style: TextStyle(color: Colors.red, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Icon(Icons.security, color: Color(0xFF00FF88), size: 48),
              const SizedBox(height: 12),
              const Text('Setup Izin', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Aktifkan semua izin agar Arbain Agent berjalan dengan baik.', style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 24),
              if (_checking)
                const Center(child: CircularProgressIndicator(color: Color(0xFF00FF88)))
              else ...[
                Expanded(
                  child: ListView(children: [
                    _buildItem(title: 'Device Admin', desc: 'Diperlukan untuk mengunci layar santri.', granted: _adminOk, onTap: _requestAdmin),
                    _buildItem(title: 'Tampil di Atas Aplikasi', desc: 'Diperlukan untuk menampilkan overlay jam tidur.', granted: _overlayOk, onTap: _requestOverlay),
                    _buildItem(title: 'Layanan Aksesibilitas', desc: 'Diperlukan untuk memblokir aplikasi tertentu.', granted: _accessibilityOk, onTap: _requestAccessibility),
                    _buildItem(title: 'Akses Penggunaan Aplikasi', desc: 'Diperlukan untuk memantau aplikasi yang dibuka.', granted: _usageOk, onTap: _requestUsage),
                    _buildItem(title: 'Baterai Tidak Dibatasi', desc: 'Agar aplikasi tetap berjalan saat HP idle.', granted: _batteryOk, onTap: _requestBattery),
                  ]),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _allGranted ? _finish : _checkAll,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _allGranted ? const Color(0xFF00FF88) : const Color(0xFF1A2A1A),
                      foregroundColor: _allGranted ? Colors.black : Colors.white54,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(_allGranted ? 'Mulai Gunakan Arbain Agent' : 'Cek Ulang Izin', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
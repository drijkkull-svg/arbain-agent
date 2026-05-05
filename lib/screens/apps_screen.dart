import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';

class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  bool _isSyncing = false;
  String _status = 'Belum disinkronkan';
  int _appCount = 0;

  Future<void> _syncApps() async {
    setState(() { _isSyncing = true; _status = 'Mengambil daftar aplikasi...'; });
    try {
      List<AppInfo> apps = await InstalledApps.getInstalledApps(excludeSystemApps: true, withIcon: false);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final appList = apps.map((app) => {
        'name': app.name,
        'packageName': app.packageName,
        'versionName': app.versionName,
        'installedAt': app.installedTimestamp,
      }).toList();

      await FirebaseFirestore.instance.collection('devices').doc(uid).update({
        'installedApps': appList,
        'appsSyncedAt': DateTime.now().toIso8601String(),
      });

      setState(() {
        _appCount = apps.length;
        _status = '${apps.length} aplikasi berhasil disinkronkan!';
        _isSyncing = false;
      });
    } catch (e) {
      setState(() { _status = 'Error: $e'; _isSyncing = false; });
    }
  }

  @override
  void initState() {
    super.initState();
    _syncApps();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text('Sinkronisasi Aplikasi', style: TextStyle(color: Color(0xFF00FF88))),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Icon(_isSyncing ? Icons.sync : Icons.check_circle,
                    color: const Color(0xFF00FF88), size: 48),
                  const SizedBox(height: 16),
                  Text(_status, style: const TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center),
                  if (_appCount > 0) ...[
                    const SizedBox(height: 8),
                    Text('Total: $_appCount aplikasi', style: const TextStyle(color: Colors.white54, fontSize: 14)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSyncing ? null : _syncApps,
                icon: _isSyncing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)) : const Icon(Icons.sync),
                label: Text(_isSyncing ? 'Menyinkronkan...' : 'Sinkronkan Ulang'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF88),
                  foregroundColor: Colors.black,
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


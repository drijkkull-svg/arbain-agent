import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppBlockerService {
  static const _channel = MethodChannel('com.example.arbain_agent/device_admin');
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Future<void> startBlocker(List<String> blockedApps) async {
    try { await _channel.invokeMethod('startAppBlocker', {'blockedApps': blockedApps}); } catch (e) { /* handled */ }
  }

  Future<void> stopBlocker() async {
    try { await _channel.invokeMethod('stopAppBlocker'); } catch (e) { /* handled */ }
  }

  Future<bool> hasUsageAccess() async {
    try { return await _channel.invokeMethod('hasUsageAccess') ?? false; } catch (e) { return false; }
  }

  Future<void> openUsageAccessSettings() async {
    try { await _channel.invokeMethod('openUsageAccessSettings'); } catch (e) { /* handled */ }
  }

  Future<void> updateBlockedApps(List<String> blockedApps) async {
    try { await _channel.invokeMethod('updateBlockedApps', {'blockedApps': blockedApps}); } catch (e) { /* handled */ }
  }

  Future<void> _saveToSharedPrefs(List<String> blockedApps) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('blocked_apps', blockedApps);
    } catch (e) { /* handled */ }
  }

  void listenBlockedApps() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _firestore.collection('devices').doc(uid).snapshots().listen((snap) async {
      if (!snap.exists) return;
      final data = snap.data()!;
      final blocked = List<String>.from(data['blockedApps'] ?? []);
      await _saveToSharedPrefs(blocked);
      if (blocked.isNotEmpty) { startBlocker(blocked); } else { stopBlocker(); }
    });
  }
}


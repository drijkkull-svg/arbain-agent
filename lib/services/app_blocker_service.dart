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

  // Get today's usage time in minutes for a package
  Future<int> _getUsageMinutesToday(String packageName) async {
    try {
      final minutes = await _channel.invokeMethod('getAppUsageMinutesToday', {'packageName': packageName});
      return (minutes ?? 0) as int;
    } catch (e) {
      return 0;
    }
  }

  String _getTodayKey() {
    const days = ['Senin','Selasa','Rabu','Kamis','Jumat','Sabtu','Minggu'];
    final weekday = DateTime.now().weekday; // 1=Monday, 7=Sunday
    return days[weekday - 1];
  }

  void listenBlockedApps() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    _firestore.collection('devices').doc(uid).snapshots().listen((snap) async {
      if (!snap.exists) return;
      final data = snap.data()!;

      // Apps that are fully blocked
      final blocked = List<String>.from(data['blockedApps'] ?? []);

      // Apps with time limits
      final appTimeLimits = Map<String, dynamic>.from(data['appTimeLimits'] ?? {});
      final todayKey = _getTodayKey();

      // Check which time-limited apps have exceeded their limit today
      final List<String> timeLimitExceeded = [];
      for (final entry in appTimeLimits.entries) {
        final packageName = entry.key;
        final limits = Map<String, dynamic>.from(entry.value ?? {});
        final limitMinutes = limits[todayKey];
        if (limitMinutes == null) continue; // no limit today

        final usedMinutes = await _getUsageMinutesToday(packageName);
        if (usedMinutes >= (limitMinutes as num).toInt()) {
          timeLimitExceeded.add(packageName);
        }
      }

      // Merge: blocked manually + exceeded time limit
      final allBlocked = {...blocked, ...timeLimitExceeded}.toList();

      await _saveToSharedPrefs(allBlocked);
      if (allBlocked.isNotEmpty) {
        startBlocker(allBlocked);
      } else {
        stopBlocker();
      }
    });
  }
}
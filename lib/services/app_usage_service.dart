import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppUsageService {
  static const _channel = MethodChannel('com.example.arbain_agent/usage_stats');

  static Future<void> syncAppUsage() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final List<dynamic>? result = await _channel.invokeMethod('getUsageStats');
      if (result == null || result.isEmpty) return;

      final filtered = result
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => (e['totalMinutes'] as int? ?? 0) > 0)
          .toList();

      filtered.sort((a, b) => (b['totalMinutes'] as int).compareTo(a['totalMinutes'] as int));

      await FirebaseFirestore.instance.collection('devices').doc(uid).update({
        'appUsage': filtered.take(20).toList(),
        'appUsageSyncedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // ignore
    }
  }
}
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
class DeviceAdminService {
  static const _channel = MethodChannel('com.example.arbain_agent/device_admin');
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  Future<bool> isAdminActive() async {
    try {
      return await _channel.invokeMethod('isAdminActive') ?? false;
    } catch (e) {
      return false;
    }
  }
  Future<void> requestAdminPermission() async {
    try {
      await _channel.invokeMethod('requestAdminPermission');
    } catch (e) {}
  }
  Future<void> lockScreen() async {
    try {
      await _channel.invokeMethod('lockScreen');
    } catch (e) {}
  }
  Future<void> setPin(String pin) async {
    try {
      await _channel.invokeMethod('setPin', {'pin': pin});
    } catch (e) {}
  }
  Future<void> clearPin() async {
    try {
      await _channel.invokeMethod('clearPin');
    } catch (e) {}
  }
  void listenLockCommand() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _firestore.collection('devices').doc(uid).snapshots().listen((snap) {
      if (!snap.exists) return;
      final data = snap.data()!;
      if (data['isRestricted'] == true) {
        final pin = data['lockPin'] ?? '000000';
        setPin(pin);
      } else {
        clearPin();
      }
      if (data['lockScreen'] == true) {
        lockScreen();
        _firestore.collection('devices').doc(uid).update({'lockScreen': false});
      }
    });
  }
}


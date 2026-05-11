import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

class GeofenceService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  Timer? _timer;

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRad(double deg) => deg * pi / 180;

  Future<Position?> _getAccurateLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) { return null; }
  }

  Future<bool> _isInsideArea() async {
    try {
      final snap = await _firestore.collection('settings').doc('ngaji_location').get();
      if (!snap.exists) return true;
      final data = snap.data()!;
      final areaLat = (data['lat'] as num?)?.toDouble();
      final areaLng = (data['lng'] as num?)?.toDouble();
      final radius = (data['radius'] as num?)?.toDouble() ?? 50.0;
      if (areaLat == null || areaLng == null) return true;
      final position = await _getAccurateLocation();
      if (position == null) return true;
      final distance = _calculateDistance(position.latitude, position.longitude, areaLat, areaLng);
      return distance <= radius;
    } catch (e) { return true; }
  }

  Future<bool> _isNgajiModeActive() async {
    try {
      final snap = await _firestore
          .collection('schedules')
          .where('isActive', isEqualTo: true)
          .where('type', isEqualTo: 'ngaji')
          .get();
      if (snap.docs.isEmpty) return false;
      final now = DateTime.now();
      final currentDay = _getDayName(now.weekday);
      final currentMinutes = now.hour * 60 + now.minute;
      for (final doc in snap.docs) {
        final data = doc.data();
        final days = List<String>.from(data['days'] ?? []);
        if (!days.contains(currentDay)) continue;
        final startMinutes = _timeToMinutes(data['startTime'] ?? '00:00');
        final endMinutes = _timeToMinutes(data['endTime'] ?? '00:00');
        bool inSchedule;
        if (startMinutes <= endMinutes) {
          inSchedule = currentMinutes >= startMinutes && currentMinutes < endMinutes;
        } else {
          inSchedule = currentMinutes >= startMinutes || currentMinutes < endMinutes;
        }
        if (inSchedule) return true;
      }
      return false;
    } catch (e) { return false; }
  }

  String _getDayName(int weekday) {
    const days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    return days[weekday - 1];
  }

  int _timeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  Future<void> _checkGeofence() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final ngajiActive = await _isNgajiModeActive();
    if (!ngajiActive) {
      // Jam ngaji selesai, clear geofence lock
      await _firestore.collection('devices').doc(uid).update({
        'isNgajiLocked': false,
      });
      return;
    }
    final insideArea = await _isInsideArea();
    await _firestore.collection('devices').doc(uid).update({
      'isNgajiLocked': !insideArea,
      'geofenceViolation': !insideArea,
      'geofenceViolationAt': !insideArea ? DateTime.now().toIso8601String() : null,
    });
  }

  void startGeofenceChecker() {
    _checkGeofence();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _checkGeofence());
  }

  void stop() {
    _timer?.cancel();
  }
}
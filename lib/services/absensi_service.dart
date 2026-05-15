import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

class AbsensiService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  Timer? _timer;
  bool _isNgajiTime = false;
  bool _sudahAbsen = false;
  DateTime? _ngajiStartTime;
  Function(bool)? onNgajiTime;
  Function()? onAbsenDeadline;

  void start({required Function(bool) onNgajiTime, required Function() onAbsenDeadline}) {
    this.onNgajiTime = onNgajiTime;
    this.onAbsenDeadline = onAbsenDeadline;
    _check();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _check());
  }

  void stop() => _timer?.cancel();

  bool get isNgajiTime => _isNgajiTime;
  bool get sudahAbsen => _sudahAbsen;

  Future<void> _check() async {
    try {
      final snap = await _firestore.collection('schedules')
          .where('isActive', isEqualTo: true)
          .get();

      final now = DateTime.now();
      final currentDay = _getDayName(now.weekday);
      final currentMinutes = now.hour * 60 + now.minute;
      bool ngajiNow = false;

      for (final doc in snap.docs) {
        final data = doc.data();
        final days = List<String>.from(data['days'] ?? []);
        if (!days.contains(currentDay)) continue;
        final startMinutes = _timeToMinutes(data['startTime'] ?? '00:00');
        final endMinutes = _timeToMinutes(data['endTime'] ?? '00:00');
        final crossMidnight = endMinutes < startMinutes;
        final inRange = crossMidnight
            ? (currentMinutes >= startMinutes || currentMinutes < endMinutes)
            : (currentMinutes >= startMinutes && currentMinutes < endMinutes);
        if (inRange) {
          ngajiNow = true;
          if (!_isNgajiTime) {
            _isNgajiTime = true;
            _sudahAbsen = false;
            _ngajiStartTime = now;
          }
          // Cek deadline absen (10 menit setelah mulai)
          if (!_sudahAbsen && _ngajiStartTime != null) {
            final menit = now.difference(_ngajiStartTime!).inMinutes;
            if (menit >= 10) onAbsenDeadline?.call();
          }
          break;
        }
      }

      if (!ngajiNow && _isNgajiTime) {
        _isNgajiTime = false;
        _sudahAbsen = false;
        _ngajiStartTime = null;
      }

      onNgajiTime?.call(ngajiNow);
    } catch (e) {}
  }

  Future<String> absen() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return 'Tidak login';

      // Cek lokasi
      final areaSnap = await _firestore.collection('settings').doc('ngaji_location').get();
      final areaData = areaSnap.data();
      if (areaData == null) return 'Area ngaji belum diset';

      final targetLat = (areaData['lat'] as num).toDouble();
      final targetLng = (areaData['lng'] as num).toDouble();
      final radius = (areaData['radius'] as num).toDouble();

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final distance = Geolocator.distanceBetween(
        position.latitude, position.longitude, targetLat, targetLng,
      );

      if (distance > radius) {
        return 'Kamu tidak berada di area ngaji! (${distance.round()} meter dari masjid)';
      }

      // Simpan absensi
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final name = userDoc.data()?['name']?.toString() ?? 'Santri';
      final today = DateTime.now().toIso8601String().substring(0, 10);

      await _firestore.collection('absensi').add({
        'santriId': uid,
        'santriName': name,
        'tanggal': today,
        'waktu': DateTime.now().toIso8601String(),
        'status': 'hadir',
        'jarak': distance.round(),
      });

      _sudahAbsen = true;
      return 'SUCCESS';
    } catch (e) {
      return 'Error: $e';
    }
  }

  int _timeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  String _getDayName(int weekday) {
    const days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    return days[weekday - 1];
  }
}
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class ScheduleService {
  final _firestore = FirebaseFirestore.instance;
  Timer? _timer;

  void startScheduleChecker(Function(bool) onRestrict) {
    _checkSchedule(onRestrict);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkSchedule(onRestrict);
    });
  }

  void stop() {
    _timer?.cancel();
  }

  Future<void> _checkSchedule(Function(bool) onRestrict) async {
    try {
      final snap = await _firestore.collection('schedules').where('isActive', isEqualTo: true).get();
      final now = DateTime.now();
      final currentDay = _getDayName(now.weekday);
      final currentMinutes = now.hour * 60 + now.minute;

      bool shouldRestrict = false;

      for (final doc in snap.docs) {
        final data = doc.data();
        final days = List<String>.from(data['days'] ?? []);
        if (!days.contains(currentDay)) continue;

        final startTime = data['startTime'] as String? ?? '21:00';
        final endTime = data['endTime'] as String? ?? '04:00';

        final startMinutes = _timeToMinutes(startTime);
        final endMinutes = _timeToMinutes(endTime);

        bool inSchedule;
        if (startMinutes <= endMinutes) {
          inSchedule = currentMinutes >= startMinutes && currentMinutes < endMinutes;
        } else {
          inSchedule = currentMinutes >= startMinutes || currentMinutes < endMinutes;
        }

        if (inSchedule) {
          shouldRestrict = true;
          break;
        }
      }

      onRestrict(shouldRestrict);
    } catch (e) { /* handled */ }
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



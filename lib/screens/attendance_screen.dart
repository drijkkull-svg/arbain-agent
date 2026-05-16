import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _isLoading = true;

  @override
  void initState() { super.initState(); _loadAttendance(); }

  Future<void> _loadAttendance() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    
    try {
      final snap = await FirebaseFirestore.instance
        .collection('absensi')
        .where('deviceId', isEqualTo: uid)
        .orderBy('tanggal', descending: true)
        .limit(30)
        .get();
      setState(() {
        _records = snap.docs.map((d) => d.data()).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hadir = _records.where((r) => r['status'] == 'hadir').length;
    final tidakHadir = _records.where((r) => r['status'] == 'tidak_hadir').length;
    final total = _records.length;
    final persen = total > 0 ? (hadir / total * 100).toStringAsFixed(0) : '0';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text('Rekap Absensi', style: TextStyle(color: Color(0xFF00FF88), fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FF88)))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                _statCard('Hadir', hadir.toString(), const Color(0xFF00FF88)),
                const SizedBox(width: 12),
                _statCard('Tidak Hadir', tidakHadir.toString(), const Color(0xFFFF4466)),
                const SizedBox(width: 12),
                _statCard('Kehadiran', '$persen%', const Color(0xFF00AAFF)),
              ]),
              const SizedBox(height: 20),
              if (_records.isEmpty)
                const Center(child: Text('Belum ada data absensi', style: TextStyle(color: Colors.white38)))
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _records.length,
                  itemBuilder: (ctx, i) {
                    final r = _records[i];
                    final isHadir = r['status'] == 'hadir';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isHadir ? const Color(0xFF00FF88) : const Color(0xFFFF4466), width: 0.5),
                      ),
                      child: Row(children: [
                        Icon(isHadir ? Icons.check_circle : Icons.cancel, color: isHadir ? const Color(0xFF00FF88) : const Color(0xFFFF4466), size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Text(r['tanggal'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 14))),
                        Text(r['scheduleName'] ?? '-', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isHadir ? const Color(0xFF00FF88).withOpacity(0.15) : const Color(0xFFFF4466).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(isHadir ? 'Hadir' : 'Absen', style: TextStyle(color: isHadir ? const Color(0xFF00FF88) : const Color(0xFFFF4466), fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ]),
                    );
                  },
                ),
            ]),
          ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.3))),
        child: Column(children: [
          Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
      ),
    );
  }
}

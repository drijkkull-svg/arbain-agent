import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  bool _paired = false;

  void _onDetect(BarcodeCapture capture) async {
    if (_paired) return;
    final barcode = capture.barcodes.first;
    final data = barcode.rawValue;
    if (data == null) return;
    try {
      final json = jsonDecode(data);
      final santriId = json['santriId'] as String?;
      if (santriId == null) return;
      setState(() { _paired = true; });
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await FirebaseFirestore.instance.collection('devices').doc(uid).set({
        'santriId': santriId,
        'isOnline': true,
        'isLostMode': false,
        'isAlarmActive': false,
        'isRestricted': false,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perangkat berhasil dipasangkan!'), backgroundColor: Color(0xFF00FF88)),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() { _paired = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text('Scan QR Pairing', style: TextStyle(color: Color(0xFF00FF88))),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: MobileScanner(onDetect: _onDetect),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: _paired
                ? const Text('Terpasang!', style: TextStyle(color: Color(0xFF00FF88), fontSize: 18, fontWeight: FontWeight.bold))
                : const Text('Arahkan kamera ke QR Code dari dashboard', style: TextStyle(color: Colors.white54), textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
  }
}

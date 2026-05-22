import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final _storage = FirebaseStorage.instance;
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _isRecording = false;
  String? _currentPath;

  bool get isRecording => _isRecording;

  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> startRecording() async {
    if (_isRecording) return;
    final hasPermission = await requestPermission();
    if (!hasPermission) return;

    try {
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentPath = '${dir.path}/audio_$timestamp.m4a';

      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 22050),
        path: _currentPath!,
      );
      _isRecording = true;

      // Update Firestore status
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        await _firestore.collection('devices').doc(uid).update({
          'isRecording': true,
          'recordingStartedAt': DateTime.now().toIso8601String(),
        });
      }

      // Auto stop after 60 seconds to save quota
      Future.delayed(const Duration(seconds: 60), () async {
        if (_isRecording) await stopRecording();
      });
    } catch (e) {
      _isRecording = false;
    }
  }

  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      await _recorder.stop();
      _isRecording = false;

      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        await _firestore.collection('devices').doc(uid).update({
          'isRecording': false,
        });
      }

      if (_currentPath != null) {
        final url = await _uploadToStorage(_currentPath!);
        // Cleanup temp file
        final file = File(_currentPath!);
        if (await file.exists()) await file.delete();
        _currentPath = null;
        return url;
      }
    } catch (e) {
      _isRecording = false;
    }
    return null;
  }

  Future<String?> _uploadToStorage(String filePath) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return null;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage.ref().child('recordings/$uid/audio_$timestamp.m4a');
      final file = File(filePath);
      final uploadTask = await ref.putFile(file);
      final url = await uploadTask.ref.getDownloadURL();

      // Save recording URL to Firestore
      await _firestore
          .collection('devices')
          .doc(uid)
          .collection('recordings')
          .add({
        'url': url,
        'timestamp': DateTime.now().toIso8601String(),
        'duration': null,
      });

      return url;
    } catch (e) {
      return null;
    }
  }

  // Listen for remote record command from dashboard
  void listenRecordCommand(Function(bool) onRecordCommand) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    _firestore.collection('devices').doc(uid).snapshots().listen((snap) async {
      if (!snap.exists) return;
      final data = snap.data()!;
      final shouldRecord = data['isRecording'] ?? false;

      if (shouldRecord && !_isRecording) {
        await startRecording();
        onRecordCommand(true);
      } else if (!shouldRecord && _isRecording) {
        await stopRecording();
        onRecordCommand(false);
      }
    });
  }

  void dispose() {
    _recorder.dispose();
  }
}

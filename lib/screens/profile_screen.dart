import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isUploading = false;
  String? _photoUrl;
  String _name = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    setState(() {
      _photoUrl = doc.data()?['photoUrl'];
      _name = doc.data()?['name'] ?? '';
    });
  }

  Future<void> _uploadPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return;

    setState(() => _isUploading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final ref = FirebaseStorage.instance.ref().child('profiles/$uid.jpg');
      await ref.putFile(File(picked.path));
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'photoUrl': url});
      setState(() { _photoUrl = url; _isUploading = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Foto profil berhasil diupload!'), backgroundColor: Color(0xFF00FF88)));
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text('Profil Saya', style: TextStyle(color: Color(0xFF00FF88), fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            GestureDetector(
              onTap: _isUploading ? null : _uploadPhoto,
              child: Stack(alignment: Alignment.bottomRight, children: [
                Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00FF88), width: 2),
                    color: const Color(0xFF111111),
                  ),
                  child: _isUploading
                    ? const CircularProgressIndicator(color: Color(0xFF00FF88))
                    : _photoUrl != null
                      ? ClipOval(child: Image.network(_photoUrl!, fit: BoxFit.cover))
                      : const Icon(Icons.person, color: Colors.white38, size: 60),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: Color(0xFF00FF88), shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt, color: Colors.black, size: 16),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            Text(_name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(FirebaseAuth.instance.currentUser?.email ?? '', style: const TextStyle(color: Colors.white38, fontSize: 14)),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isUploading ? null : _uploadPhoto,
                icon: const Icon(Icons.upload),
                label: const Text('Ganti Foto Profil'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF88),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isUploading = false;
  String? _photoUrl;
  String _name = '';
  String _email = '';
  String _kamar = '';
  String _version = '';
  int _hadirCount = 0;
  int _izinCount = 0;
  int _alphaCount = 0;

  static const _bg = Color(0xFF070f07);
  static const _green = Color(0xFF4ade80);
  static const _card = Color(0xFF0d0d0d);
  static const _cardBorder = Color(0xFF1a3a22);

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadVersion();
    _loadAbsensi();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = info.version);
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (mounted) setState(() {
      _photoUrl = doc.data()?['photoUrl'];
      _name = doc.data()?['name'] ?? '';
      _email = FirebaseAuth.instance.currentUser?.email ?? '';
      _kamar = doc.data()?['kamar'] ?? '';
    });
  }

  Future<void> _loadAbsensi() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final now = DateTime.now();
      final snap = await FirebaseFirestore.instance
          .collection('attendance')
          .where('santriId', isEqualTo: uid)
          .get();
      int hadir = 0, izin = 0, alpha = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        try {
          final date = DateTime.parse(data['timestamp'].toString());
          if (date.month == now.month && date.year == now.year) {
            final status = data['status'] ?? '';
            if (status == 'hadir') hadir++;
            else if (status == 'izin') izin++;
            else if (status == 'alpha') alpha++;
          }
        } catch (_) {}
      }
      if (mounted) setState(() { _hadirCount = hadir; _izinCount = izin; _alphaCount = alpha; });
    } catch (e) { debugPrint('loadAbsensi error: $e'); }
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
      if (mounted) setState(() { _photoUrl = url; _isUploading = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Foto profil berhasil diupload!'), backgroundColor: Color(0xFF16a34a)));
    } catch (e) {
      if (mounted) setState(() => _isUploading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light),
      child: Scaffold(
        backgroundColor: _bg,
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.8, -1.0),
              radius: 1.2,
              colors: [Color(0xFF0a2e12), _bg],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // TOP BAR
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                  child: Row(children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF1e1e1e))),
                        child: const Icon(Icons.arrow_back_ios_new, color: Colors.white54, size: 16),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('Profil Santri', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ]),
                ),

                const SizedBox(height: 24),

                // AVATAR
                Center(
                  child: GestureDetector(
                    onTap: _isUploading ? null : _uploadPhoto,
                    child: Stack(alignment: Alignment.bottomRight, children: [
                      Container(
                        width: 90, height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _green, width: 2),
                          color: const Color(0xFF0f2d1a),
                        ),
                        child: _isUploading
                            ? const CircularProgressIndicator(color: _green, strokeWidth: 2)
                            : _photoUrl != null
                                ? ClipOval(child: Image.network(_photoUrl!, fit: BoxFit.cover))
                                : const Icon(Icons.person, color: Color(0xFF4a6e50), size: 44),
                      ),
                      Container(
                        width: 26, height: 26,
                        decoration: BoxDecoration(color: const Color(0xFF16a34a), shape: BoxShape.circle, border: Border.all(color: _bg, width: 2)),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 13),
                      ),
                    ]),
                  ),
                ),

                const SizedBox(height: 14),

                Center(child: Text(_name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700))),
                const SizedBox(height: 4),
                Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  const Text('Online', style: TextStyle(color: _green, fontSize: 12, fontWeight: FontWeight.w500)),
                ])),

                const SizedBox(height: 22),

                // STATISTIK
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(18), border: Border.all(color: _cardBorder)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('STATISTIK BULAN INI', style: TextStyle(color: Color(0xFF2a4a2a), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 14),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                        _statItem('$_hadirCount', 'Hadir', _green),
                        _statItem('$_izinCount', 'Izin', const Color(0xFFfbbf24)),
                        _statItem('$_alphaCount', 'Alpha', const Color(0xFFf87171)),
                      ]),
                    ]),
                  ),
                ),

                const SizedBox(height: 12),

                // INFO
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(18), border: Border.all(color: _cardBorder)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('INFO SANTRI', style: TextStyle(color: Color(0xFF2a4a2a), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 14),
                      _infoRow(Icons.email_outlined, 'Email', _email),
                      _divider(),
                      _infoRow(Icons.bed_outlined, 'Kamar', _kamar.isNotEmpty ? _kamar : '-'),
                      _divider(),
                      _infoRow(Icons.info_outline, 'Versi App', 'v$_version'),
                    ]),
                  ),
                ),

                const SizedBox(height: 12),

                // GANTI FOTO
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: GestureDetector(
                    onTap: _isUploading ? null : _uploadPhoto,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF071f0f),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF1a4a22)),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.camera_alt_outlined, color: _green, size: 18),
                        const SizedBox(width: 8),
                        Text(_isUploading ? 'Mengupload...' : 'Ganti Foto Profil', style: const TextStyle(color: _green, fontSize: 14, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statItem(String value, String label, Color color) {
    return Column(children: [
      Text(value, style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: Color(0xFF4a6e50), fontSize: 11)),
    ]);
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Icon(icon, color: const Color(0xFF4a6e50), size: 16),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: Color(0xFF4a6e50), fontSize: 13)),
        const Spacer(),
        Text(value, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ]),
    );
  }

  Widget _divider() => Container(height: 0.5, color: const Color(0xFF1a2a1a));
}

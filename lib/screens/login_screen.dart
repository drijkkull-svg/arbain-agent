import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _error;
  String _version = '';

  static const _bg = Color(0xFF070f07);
  static const _green = Color(0xFF4ade80);
  static const _card = Color(0xFF0d0d0d);

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = info.version);
  }

  Future<void> _login() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (!doc.exists) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'id': user.uid,
            'email': user.email,
            'name': user.displayName ?? user.email?.split('@')[0] ?? 'Santri',
            'role': 'Santri',
            'createdAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          });
        }
      }
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null && user != null) {
        await FirebaseFirestore.instance.collection('devices').doc(user.uid).set({
          'fcmToken': fcmToken,
        }, SetOptions(merge: true));
      }
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    } catch (e) {
      setState(() { _error = 'Email atau password salah.'; });
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _forgotPassword() async {
    final emailController = TextEditingController(text: _emailController.text.trim());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0f0f0f),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Lupa Password', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Masukkan email kamu, kami akan kirim link reset password.', style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 16),
          TextField(
            controller: emailController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'nama@pondok.id',
              hintStyle: const TextStyle(color: Color(0xFF2a4a2a), fontSize: 13),
              prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF4a6e50), size: 18),
              filled: true,
              fillColor: const Color(0xFF0d0d0d),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1a3a22))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _green, width: 1.5)),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) return;
              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link reset password telah dikirim ke email kamu!'), backgroundColor: Color(0xFF16a34a)),
                );
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Email tidak ditemukan.'), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16a34a), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
            child: const Text('Kirim', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 32),
                    Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(color: const Color(0xFF16a34a), borderRadius: BorderRadius.circular(22)),
                      child: const Icon(Icons.shield, color: Colors.white, size: 40),
                    ),
                    const SizedBox(height: 18),
                    const Text('Arbain Agent', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                    const SizedBox(height: 6),
                    const Text('SISTEM MONITORING SANTRI', style: TextStyle(color: Color(0xFF2a4a2a), fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF071f0f),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: const Color(0xFF1a4a22)),
                      ),
                      child: const Text("Pondok Pesantren Al-Mubarok Al-Arba'in", style: TextStyle(color: Color(0xFF4ade80), fontSize: 10, fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(height: 44),
                    Align(alignment: Alignment.centerLeft, child: const Text('EMAIL', style: TextStyle(color: Color(0xFF2a4a2a), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700))),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'nama@pondok.id',
                        hintStyle: const TextStyle(color: Color(0xFF2a4a2a), fontSize: 13),
                        prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF4a6e50), size: 18),
                        filled: true,
                        fillColor: _card,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF1a3a22))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _green, width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(alignment: Alignment.centerLeft, child: const Text('PASSWORD', style: TextStyle(color: Color(0xFF2a4a2a), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700))),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        hintStyle: const TextStyle(color: Color(0xFF2a4a2a), fontSize: 13),
                        prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF4a6e50), size: 18),
                        suffixIcon: GestureDetector(
                          onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                          child: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: const Color(0xFF4a6e50), size: 18),
                        ),
                        filled: true,
                        fillColor: _card,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF1a3a22))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _green, width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: _forgotPassword,
                        child: const Text('Lupa Password?', style: TextStyle(color: Color(0xFF4ade80), fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: const Color(0xFF1a0808), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF3a1010))),
                        child: Row(children: [
                          const Icon(Icons.error_outline, color: Color(0xFFf87171), size: 16),
                          const SizedBox(width: 8),
                          Text(_error!, style: const TextStyle(color: Color(0xFFf87171), fontSize: 13)),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16a34a),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                            : const Text('Masuk', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.5)),
                      ),
                    ),
                    const SizedBox(height: 44),
                    const Text('Perangkat ini dikontrol oleh Tim Oraasis', style: TextStyle(color: Color(0xFF1a2a1a), fontSize: 11), textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    Text('v$_version', style: const TextStyle(color: Color(0xFF1a2a1a), fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

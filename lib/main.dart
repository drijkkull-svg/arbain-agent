import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/home_screen.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ArbainAgentApp());
}
class ArbainAgentApp extends StatelessWidget {
  const ArbainAgentApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arbain Agent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00FF88),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: Color(0xFF0A0A0A),
              body: Center(child: CircularProgressIndicator(color: Color(0xFF00FF88))),
            );
          }
          if (snapshot.hasData) {
            return FutureBuilder<bool>(
              future: SharedPreferences.getInstance().then((p) => p.getBool('setup_done') ?? false),
              key: const ValueKey('home_check'),
              builder: (context, snap) {
                if (snap.data == true) return const HomeScreen();
                return const SetupScreen();
              },
            );
          }
          return const LoginScreen();
        },
      ),
    );
  }
}

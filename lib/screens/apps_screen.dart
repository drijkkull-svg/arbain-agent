import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';

class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});
  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  bool _isSyncing = false;
  List<AppInfo> _apps = [];
  String _search = "";

  Future<void> _syncApps() async {
    setState(() => _isSyncing = true);
    try {
      List<AppInfo> apps = await InstalledApps.getInstalledApps(excludeSystemApps: true, withIcon: false);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection("devices").doc(uid).update({
          "installedApps": apps.map((a) => {"name": a.name, "packageName": a.packageName, "versionName": a.versionName}).toList(),
          "appsSyncedAt": DateTime.now().toIso8601String(),
        });
      }
      setState(() { _apps = apps; _isSyncing = false; });
    } catch (e) {
      setState(() => _isSyncing = false);
    }
  }

  @override
  void initState() { super.initState(); _syncApps(); }

  @override
  Widget build(BuildContext context) {
    final filtered = _apps.where((a) => a.name.toLowerCase().contains(_search.toLowerCase())).toList();
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: Text("Aplikasi (${_apps.length})", style: const TextStyle(color: Color(0xFF00FF88), fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [IconButton(
          icon: _isSyncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFF00FF88), strokeWidth: 2)) : const Icon(Icons.sync, color: Color(0xFF00FF88)),
          onPressed: _isSyncing ? null : _syncApps,
        )],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Cari aplikasi...",
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              filled: true, fillColor: const Color(0xFF111111),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        Expanded(child: _isSyncing && _apps.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FF88)))
          : ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (ctx, i) {
                final app = filtered[i];
                return ListTile(
                  leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.android, color: Color(0xFF00FF88), size: 24)),
                  title: Text(app.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: Text(app.packageName, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  trailing: Text(app.versionName, style: const TextStyle(color: Colors.white24, fontSize: 11)),
                );
              },
            )),
      ]),
    );
  }
}

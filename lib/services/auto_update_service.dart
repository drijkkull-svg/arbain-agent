import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

class AutoUpdateService {
  final _firestore = FirebaseFirestore.instance;

  Future<void> checkUpdate(BuildContext context) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final doc = await _firestore.collection('config').doc('app_version').get();
      if (!doc.exists) return;

      final latestVersion = doc.data()?['version'] ?? '';
      final apkUrl = doc.data()?['apk_url'] ?? '';

      if (latestVersion == currentVersion || apkUrl.isEmpty) return;

      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF111111),
            title: const Text('Update Tersedia', style: TextStyle(color: Color(0xFF00FF88))),
            content: Text(
              'Versi baru ($latestVersion) tersedia.\nVersi kamu: $currentVersion',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Nanti', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _downloadAndInstall(context, apkUrl);
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF88)),
                child: const Text('Update Sekarang', style: TextStyle(color: Colors.black)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _downloadAndInstall(BuildContext context, String apkUrl) async {
    final status = await Permission.requestInstallPackages.request();
    if (!status.isGranted) return;

    final dir = await getExternalStorageDirectory();
    final savePath = '${dir!.path}/arbain_update.apk';

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) {
            double progress = 0;
            return AlertDialog(
              backgroundColor: const Color(0xFF111111),
              title: const Text('Mengunduh...', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: progress,
                    color: const Color(0xFF00FF88),
                  ),
                  const SizedBox(height: 8),
                  Text('${(progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white54)),
                ],
              ),
            );
          },
        ),
      );
    }

    await Dio().download(
      apkUrl,
      savePath,
      onReceiveProgress: (received, total) {},
    );

    if (context.mounted) Navigator.pop(context);
    await OpenFilex.open(savePath);
  }
}



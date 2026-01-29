import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'app.dart';
import 'services/api_service.dart';
import 'services/background_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (FlutterCryptography.isPluginPresent) {
    Cryptography.instance = FlutterCryptography.defaultInstance;
    debugPrint('🔐 [MAIN] Using native AES-GCM (cryptography_flutter)');
  }
  debugPrint('');
  debugPrint('🚀 [MAIN] ========== APP STARTING ==========');
  debugPrint('🚀 [MAIN] main() function called');
  debugPrint('🚀 [MAIN] WidgetsFlutterBinding initialized');
  ApiService.getDeviceId().then((id) {
    debugPrint('📱 [MAIN] Device ID: $id');
  });
  if (Platform.isAndroid) {
    try {
      await initWorkManager();
      debugPrint('🚀 [MAIN] WorkManager initialized');
    } catch (e) {
      debugPrint('⚠️ [MAIN] WorkManager init failed: $e');
    }
  }
  debugPrint('🚀 [MAIN] Running MyApp...');
  debugPrint('');
  runApp(const MyApp());
}

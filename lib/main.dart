import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:webview_win_floating/webview_plugin.dart';
import 'app.dart';
import 'services/api_service.dart';
import 'services/background_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite FFI for Windows/Linux (required before any openDatabase call)
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    debugPrint('📂 [MAIN] sqflite FFI initialized for desktop');
  }

  // Register WebView platform for Windows/Linux (required before using WebViewWidget)
  if (Platform.isWindows || Platform.isLinux) {
    WindowsWebViewPlatform.registerWith();
    debugPrint('🌐 [MAIN] WebView platform set for desktop');
  }

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

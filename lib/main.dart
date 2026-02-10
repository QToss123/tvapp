import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show debugPrint, FlutterError, FlutterErrorDetails;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:webview_win_floating/webview_plugin.dart';
import 'app.dart';
import 'services/api_service.dart';
import 'services/background_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Prevent uncaught errors from crashing the app
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('FlutterError: ${details.exception}\n${details.stack}');
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('Uncaught error: $error\n$stack');
    return true; // we handled it, don't crash
  };

  // Launch UI immediately so the app shows and keeps device connection (avoids "Lost connection" on Android TV / emulator)
  runApp(const MyApp());
  _deferredInit();
}

void _deferredInit() {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    debugPrint('[MAIN] sqflite FFI initialized for desktop');
    WindowsWebViewPlatform.registerWith();
    debugPrint('[MAIN] WebView platform set for desktop');
  }
  try {
    if (FlutterCryptography.isPluginPresent) {
      Cryptography.instance = FlutterCryptography.defaultInstance;
      debugPrint('[MAIN] Using native AES-GCM (cryptography_flutter)');
    }
  } catch (e) {
    debugPrint('[MAIN] Cryptography plugin not used: $e');
  }
  ApiService.getDeviceId().then((id) => debugPrint('[MAIN] Device ID: $id')).catchError((e) => debugPrint('[MAIN] Device ID failed: $e'));
  if (Platform.isAndroid) {
    initWorkManager().then((_) => debugPrint('[MAIN] WorkManager initialized')).catchError((e) => debugPrint('[MAIN] WorkManager init failed: $e'));
  }
  try {
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else if (Platform.isWindows || Platform.isLinux) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  } catch (e) {
    debugPrint('[MAIN] Full screen mode not supported: $e');
  }
}

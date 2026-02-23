import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:webview_win_floating/webview_plugin.dart';
import 'app.dart';
import 'services/background_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Prevent uncaught errors from crashing the app
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
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
  }
  if (Platform.isWindows) {
    WindowsWebViewPlatform.registerWith();
  }
  try {
    if (FlutterCryptography.isPluginPresent) {
      Cryptography.instance = FlutterCryptography.defaultInstance;
    }
  } catch (e, st) {
    debugPrint('[Main] CryptographyFlutter init failed: $e\n$st');
  }
  try {
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      initWorkManager().catchError((e, st) {
        debugPrint('[Main] initWorkManager failed: $e\n$st');
      });
    } else if (Platform.isWindows || Platform.isLinux) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  } catch (e, st) {
    debugPrint('[Main] SystemChrome failed: $e\n$st');
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'app.dart';
import 'services/api_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('');
  debugPrint('🚀 [MAIN] ========== APP STARTING ==========');
  debugPrint('🚀 [MAIN] main() function called');
  debugPrint('🚀 [MAIN] WidgetsFlutterBinding initialized');
  ApiService.getDeviceId().then((id) {
    debugPrint('📱 [MAIN] Device ID: $id');
  });
  debugPrint('🚀 [MAIN] Running MyApp...');
  debugPrint('');
  runApp(const MyApp());
}

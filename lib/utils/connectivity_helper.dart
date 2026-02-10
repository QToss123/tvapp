import 'dart:io';
import 'package:flutter/foundation.dart';

/// Helper class for checking network connectivity
class ConnectivityHelper {
  static const int _maxAttempts = 3;
  static const Duration _attemptTimeout = Duration(seconds: 4);
  static const Duration _retryDelay = Duration(milliseconds: 600);

  /// Checks if device has internet connectivity.
  /// Uses DNS lookup (google.com) with retries. Never throws.
  static Future<bool> hasInternetConnection() async {
    try {
      for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
        try {
          final result = await InternetAddress.lookup('google.com')
              .timeout(_attemptTimeout);
          if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
            if (kDebugMode) {
              debugPrint(attempt > 1
                  ? '✅ Internet connection available (after retry)'
                  : '✅ Internet connection available');
            }
            return true;
          }
        } catch (e) {
          if (attempt < _maxAttempts) {
            await Future.delayed(_retryDelay);
            continue;
          }
          if (kDebugMode) debugPrint('❌ No internet connection: $e');
          return false;
        }
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('❌ Connectivity check error: $e');
      if (kDebugMode) debugPrint('$st');
      return false;
    }
    return false;
  }

  /// Checks connectivity with a specific host
  static Future<bool> checkHostReachable(String host) async {
    try {
      final result = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      debugPrint('Cannot reach host $host: $e');
      return false;
    }
  }
}

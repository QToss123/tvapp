import 'dart:io';
import 'package:flutter/foundation.dart';

/// Helper class for checking network connectivity
class ConnectivityHelper {
  /// Checks if device has internet connectivity
  /// Returns true if connected, false otherwise
  static Future<bool> hasInternetConnection() async {
    try {
      // Try to connect to a reliable server (Google DNS or a common endpoint)
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        debugPrint('✅ Internet connection available');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ No internet connection: $e');
      return false;
    }
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

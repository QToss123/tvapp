import 'dart:io';

import 'package:http/http.dart' as http;

/// Helper class for checking network connectivity
class ConnectivityHelper {
  static const int _maxAttempts = 2;
  static const Duration _attemptTimeout = Duration(seconds: 5);
  static const Duration _retryDelay = Duration(milliseconds: 500);

  /// Checks if device has internet connectivity.
  /// Uses an HTTP request (not just DNS) so offline is detected reliably
  /// (e.g. on Windows, DNS cache can make lookup succeed when there is no internet).
  /// Never throws.
  static Future<bool> hasInternetConnection() async {
    try {
      for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
        try {
          final response = await http
              .get(
                Uri.parse('https://www.google.com/generate_204'),
              )
              .timeout(_attemptTimeout);
          if (response.statusCode == 204 || response.statusCode == 200) {
            return true;
          }
        } catch (e) {
          if (attempt < _maxAttempts) {
            await Future.delayed(_retryDelay);
            continue;
          }
          return false;
        }
      }
    } catch (e) {
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
      return false;
    }
  }
}

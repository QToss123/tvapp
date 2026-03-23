import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Platform-aware service for opening web content.
/// On Linux, opens URLs in the system browser to avoid WebView instability.
/// On Android and Windows, callers keep using embedded WebView; this service
/// is used only when the app explicitly wants to open a URL externally (e.g. Linux).
class WebLauncherService {
  WebLauncherService._();
  static final WebLauncherService instance = WebLauncherService._();

  /// Opens [url] in the appropriate context for the platform.
  ///
  /// - **Linux**: Opens in the system default browser (external application).
  /// - **Android / Windows / others**: Does not open externally; callers continue
  ///   to use embedded WebView for in-app content. This method can still be
  ///   used on non-Linux to open a URL externally if needed.
  ///
  /// Returns `true` if the URL was launched successfully, `false` otherwise.
  /// Throws no exceptions; errors are logged and reflected in the return value.
  static Future<bool> openWebContent(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (!uri.hasScheme || (!uri.isScheme('http') && !uri.isScheme('https')))) {
      debugPrint('[WebLauncherService] Invalid or unsupported URL: $url');
      return false;
    }

    if (Platform.isLinux) {
      try {
        if (kDebugMode) {
          debugPrint('Opening external browser on Linux');
        }
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched) {
          debugPrint('[WebLauncherService] launchUrl returned false for: $url');
          return false;
        }
        return true;
      } catch (e, st) {
        debugPrint('[WebLauncherService] Failed to open browser: $e');
        debugPrint(st.toString());
        return false;
      }
    }

    // Non-Linux: callers use WebView; no external launch by default.
    return false;
  }
}

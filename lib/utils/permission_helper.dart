import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Helper class for handling runtime permissions (Android only; Windows/Linux need none)
class PermissionHelper {
  /// Requests storage permissions needed for folder access (internal + external + USB).
  /// On Android 11+: requests MANAGE_EXTERNAL_STORAGE (all files access).
  /// On Android 10 and below: requests READ/WRITE_EXTERNAL_STORAGE.
  /// Returns true if permissions are granted, false otherwise.
  static Future<bool> requestStoragePermissions() async {
    if (!Platform.isAndroid) return true;
    try {
      // Android 11+: MANAGE_EXTERNAL_STORAGE opens settings for "All files access"
      try {
        final status = await ph.Permission.manageExternalStorage.status;
        if (status.isGranted) {
          debugPrint('Manage external storage already granted');
          return true;
        }
        final requested = await ph.Permission.manageExternalStorage.request();
        if (requested.isGranted) return true;
        if (requested.isPermanentlyDenied) {
          debugPrint('Manage external storage permanently denied');
          return false;
        }
      } catch (e) {
        debugPrint('Manage external storage not available: $e');
      }

      // Android 10 and below: READ/WRITE_EXTERNAL_STORAGE
      try {
        final status = await ph.Permission.storage.status;
        if (status.isGranted) return true;
        final requested = await ph.Permission.storage.request();
        if (requested.isGranted) return true;
        if (requested.isPermanentlyDenied) return false;
      } catch (e) {
        debugPrint('Storage permission error: $e');
      }
      return false;
    } catch (e) {
      debugPrint('Error requesting storage permissions: $e');
      return false;
    }
  }

  /// Opens the All Files Access settings screen (Android 11+).
  /// Call when MANAGE_EXTERNAL_STORAGE is denied so user can grant it manually.
  /// Required for folder selection from USB drives in release APK.
  static Future<bool> openAllFilesAccessSettings() async {
    if (!Platform.isAndroid) return true;
    try {
      if (await ph.Permission.manageExternalStorage.isGranted) return true;
      // request() opens the system "All files access" permission screen on Android 11+
      await ph.Permission.manageExternalStorage.request();
      return await ph.Permission.manageExternalStorage.isGranted;
    } catch (e) {
      debugPrint('Open all files access error: $e');
      // Fallback: open app settings so user can find "Files and media" / "All files"
      return await ph.openAppSettings();
    }
  }

  /// Checks if storage permissions are granted (Android only)
  static Future<bool> hasStoragePermissions() async {
    if (!Platform.isAndroid) return true;
    try {
      try {
        if (await ph.Permission.manageExternalStorage.isGranted) return true;
      } catch (_) {}
      try {
        if (await ph.Permission.storage.isGranted) return true;
      } catch (_) {}
      return false;
    } catch (e) {
      debugPrint('Error checking storage permissions: $e');
      return false;
    }
  }

  /// Opens app settings for manual permission grant
  static Future<bool> openAppSettings() async {
    try {
      return await ph.openAppSettings();
    } catch (e) {
      debugPrint('Error opening app settings: $e');
      return false;
    }
  }
}

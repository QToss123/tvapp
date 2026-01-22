import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:flutter/foundation.dart';

/// Helper class for handling runtime permissions
class PermissionHelper {
  /// Requests storage permissions needed for folder access
  /// Returns true if permissions are granted, false otherwise
  static Future<bool> requestStoragePermissions() async {
    try {
      // Check Android version and request appropriate permissions
      // For Android 13+ (API 33+), use scoped storage permissions
      // For Android 11-12, use MANAGE_EXTERNAL_STORAGE if available
      // For older versions, use READ_EXTERNAL_STORAGE
      
      // Try to request manage external storage first (Android 11+)
      try {
        final manageStorageStatus = await ph.Permission.manageExternalStorage.status;
        if (manageStorageStatus.isGranted) {
          debugPrint('Manage external storage permission already granted');
          return true;
        }

        // Request manage external storage (for full access on Android 11+)
        final requestedStatus = await ph.Permission.manageExternalStorage.request();
        if (requestedStatus.isGranted) {
          debugPrint('Manage external storage permission granted');
          return true;
        }
      } catch (e) {
        // manageExternalStorage might not be available, try storage permission
        debugPrint('Manage external storage not available: $e');
      }

      // Fallback: Request read storage permission
      try {
        final storageStatus = await ph.Permission.storage.status;
        if (storageStatus.isGranted) {
          debugPrint('Storage permission already granted');
          return true;
        }

        final requestedStatus = await ph.Permission.storage.request();
        if (requestedStatus.isGranted) {
          debugPrint('Storage permission granted');
          return true;
        }

        // Check if permanently denied
        if (requestedStatus.isPermanentlyDenied) {
          debugPrint('Storage permission permanently denied');
          return false;
        }

        debugPrint('Storage permission denied: $requestedStatus');
        return false;
      } catch (e) {
        debugPrint('Error requesting storage permission: $e');
        return false;
      }
    } catch (e) {
      debugPrint('Error requesting storage permissions: $e');
      // If permission_handler fails, try to continue anyway
      // Some devices might not need runtime permissions
      return false;
    }
  }

  /// Checks if storage permissions are granted
  static Future<bool> hasStoragePermissions() async {
    try {
      // Check manage external storage first
      try {
        final status = await ph.Permission.manageExternalStorage.status;
        if (status.isGranted) {
          return true;
        }
      } catch (e) {
        // manageExternalStorage might not be available
        debugPrint('Cannot check manage external storage: $e');
      }

      // Check regular storage permission
      try {
        final status = await ph.Permission.storage.status;
        if (status.isGranted) {
          return true;
        }
      } catch (e) {
        debugPrint('Cannot check storage permission: $e');
      }

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

import 'package:shared_preferences/shared_preferences.dart';

/// Helper class to initialize dummy/test data for the app
class DummyData {
  // Dummy license data
  static const String dummyLicenseNumber = 'CLA-CL21-S10-28RZBFKP0T'; // Test license
  static String get dummyExpiryDate {
    // Set expiry to 1 year from now
    final expiry = DateTime.now().add(const Duration(days: 365));
    return '${expiry.year}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')}';
  }

  /// Initialize dummy license data for testing
  static Future<void> initializeDummyLicense() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('licenseNumber', dummyLicenseNumber);
    await prefs.setString('licenseExpiryDate', dummyExpiryDate);
    await prefs.setBool('licenseActivated', true);
    await prefs.setString('syncType', 'online');
    await prefs.setString('storageLocation', 'internal');
  }

  /// Clear all dummy data
  static Future<void> clearDummyData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('licenseNumber');
    await prefs.remove('licenseActivated');
    await prefs.remove('licenseExpiryDate');
    await prefs.remove('syncType');
    await prefs.remove('storageLocation');
  }

  /// Check if dummy data is initialized
  static Future<bool> isDummyDataInitialized() async {
    final prefs = await SharedPreferences.getInstance();
    final licenseNumber = prefs.getString('licenseNumber') ?? '';
    return licenseNumber == dummyLicenseNumber;
  }
}

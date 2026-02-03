import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    debugPrint('');
    debugPrint('🌅 [SPLASH] ========== SPLASH SCREEN INIT ==========');
    debugPrint('🌅 [SPLASH] App is launching...');
    debugPrint('🌅 [SPLASH] SplashScreen initState() called');
    _checkLicenseAndNavigate();
  }

  Future<void> _checkLicenseAndNavigate() async {
    // Wait for splash screen display
    debugPrint('🌅 [SPLASH] Waiting 2 seconds before navigation...');
    await Future.delayed(const Duration(seconds: 2));
    
    if (!mounted) {
      debugPrint('⚠️ [SPLASH] Widget not mounted, aborting navigation');
      return;
    }
    
    // Check license activation and expiry
    debugPrint('🌅 [SPLASH] Checking license validity...');
    final bool licenseValid = await _isLicenseValid();
    debugPrint('🌅 [SPLASH] License valid: $licenseValid');
    
    if (!mounted) {
      debugPrint('⚠️ [SPLASH] Widget not mounted after license check, aborting');
      return;
    }
    
    // Navigate to home screen (it will show empty state if license not valid)
    debugPrint('🌅 [SPLASH] Navigating to HomeScreen using pushReplacementNamed...');
    debugPrint('🌅 [SPLASH] This will replace SplashScreen with HomeScreen');
    Navigator.pushReplacementNamed(context, AppRoutes.home);
    debugPrint('🌅 [SPLASH] Navigation command sent - HomeScreen should initialize now');
    debugPrint('🌅 [SPLASH] ===========================================');
  }

  Future<bool> _isLicenseValid() async {
    final prefs = await SharedPreferences.getInstance();
    final licenseNumber = prefs.getString('licenseNumber') ?? '';
    final isLicenseActivated = prefs.getBool('licenseActivated') ?? false;
    final expiryDateStr = prefs.getString('licenseExpiryDate') ?? '';
    
    // Check if license is activated
    if (licenseNumber.isEmpty || !isLicenseActivated) {
      return false;
    }
    
    // Check if expiry date is provided
    if (expiryDateStr.isEmpty) {
      return false;
    }
    
    // Check if license has expired
    try {
      final expiryDate = DateTime.parse(expiryDateStr);
      final now = DateTime.now();
      if (now.isAfter(expiryDate)) {
        // License has expired - deactivate it
        await prefs.setBool('licenseActivated', false);
        return false;
      }
    } catch (e) {
      // Invalid date format
      return false;
    }
    
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/app_icon.png',
              width: 200,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Text(
                'BurlingtonEnglish',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Loading...',
              style: TextStyle(fontSize: 14, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

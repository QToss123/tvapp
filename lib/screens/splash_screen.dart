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
    _checkLicenseAndNavigate();
  }

  Future<void> _checkLicenseAndNavigate() async {
    // Wait for splash screen display
    await Future.delayed(const Duration(seconds: 2));
    
    if (!mounted) return;
    
    // Check license activation and expiry
    final bool licenseValid = await _isLicenseValid();
    
    if (!mounted) return;
    
    // Navigate to home screen (it will show empty state if license not valid)
    Navigator.pushReplacementNamed(context, AppRoutes.home);
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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.menu_book_rounded, size: 64),
            SizedBox(height: 12),
            Text(
              'Bookshelf',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text('Loading...', style: TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

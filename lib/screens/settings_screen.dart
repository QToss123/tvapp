import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../routes.dart';
import '../widgets/file_browser.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../utils/permission_helper.dart';
import '../utils/connectivity_helper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _kLicenseNumber = 'licenseNumber';
  static const _kLicenseActivated = 'licenseActivated';
  static const _kLicenseExpiryDate = 'licenseExpiryDate';
  static const _kLicenseToken = 'license_token';
  static const _kSyncType = 'syncType';
  static const _kStorageLocation = 'storageLocation';
  static const _kSyncCompleted = 'syncCompleted';

  final TextEditingController _licenseController = TextEditingController();
  final FocusNode _licenseFocusNode = FocusNode();
  final FocusNode _activateButtonFocusNode = FocusNode();
  bool _isLicenseActivated = false;
  String _syncType = 'online';
  String _storageLocation = 'Not selected';

  final List<String> _syncTypes = ['online', 'from external'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _licenseController.dispose();
    _licenseFocusNode.dispose();
    _activateButtonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _licenseController.text = prefs.getString(_kLicenseNumber) ?? 'CLA-CL62-S46-EN610E41YR';
      _isLicenseActivated = prefs.getBool(_kLicenseActivated) ?? false;
      _syncType = prefs.getString(_kSyncType) ?? 'online';
      _storageLocation = prefs.getString(_kStorageLocation) ?? 'Not selected';
    });
  }

  Future<void> _activateLicense() async {
    final licenseValue = _licenseController.text.trim();
    
    if (licenseValue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a license number'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    // Check internet connectivity before license validation/activation
    final hasInternet = await ConnectivityHelper.hasInternetConnection();
    if (!hasInternet) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Internet connection required for license activation. Please check your network connection.'),
            duration: Duration(seconds: 4),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    
    // Show loading dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Validating license...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      // Step 1: Validate license to get token
      final validateResult = await ApiService.validateLicense(licenseValue);
      
      if (validateResult['success'] != true || validateResult['valid'] != true) {
        // Close loading dialog
        if (mounted) {
          Navigator.of(context).pop();
        }
        
        // License validation failed
        final errorMessage = validateResult['message'] ?? 'License validation failed';
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              duration: const Duration(seconds: 4),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Step 2: Get token from validation response
      final token = validateResult['token'];
      debugPrint('Token from validation result: ${token != null ? (token.toString().substring(0, 20) + '...') : 'NULL'}');
      
      if (token == null || token.toString().isEmpty) {
        debugPrint('⚠️ WARNING: No token returned from validation response!');
        debugPrint('Validation result keys: ${validateResult.keys}');
        debugPrint('Full validation result: $validateResult');
        
        // Check if we have a stored token from previous activation
        final prefs = await SharedPreferences.getInstance();
        final existingToken = prefs.getString(_kLicenseToken);
        if (existingToken != null && existingToken.isNotEmpty) {
          debugPrint('✅ Found existing token in storage, using it: ${existingToken.substring(0, 20)}...');
          // Continue with activation using existing token
        } else {
          debugPrint('❌ No token found and no existing token in storage!');
          // No token returned - save license based on validation result
          final expiryDateStr = validateResult['expiryDate']?.toString() ?? '';
          await prefs.setString(_kLicenseNumber, licenseValue);
          if (expiryDateStr.isNotEmpty) {
            await prefs.setString(_kLicenseExpiryDate, expiryDateStr);
          }
          await prefs.setBool(_kLicenseActivated, true);
          
          // Close loading dialog
          if (mounted) {
            Navigator.of(context).pop();
          }
          
          setState(() {
            _isLicenseActivated = true;
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('License validated but no token received. Please contact support.'),
                duration: Duration(seconds: 4),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      // Step 3: Save token immediately after validation (in case activation fails)
      final prefs = await SharedPreferences.getInstance();
      final tokenString = token?.toString();
      
      if (tokenString == null || tokenString.isEmpty) {
        debugPrint('❌ ERROR: Cannot proceed - token is null or empty!');
        if (mounted) {
          Navigator.of(context).pop();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: No token received from validation. Please try again.'),
              duration: Duration(seconds: 4),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      // Save the token
      await prefs.setString(_kLicenseToken, tokenString);
      debugPrint('✅ Token saved after validation: ${tokenString.substring(0, 20)}...');
      debugPrint('Token saved with key: $_kLicenseToken');
      debugPrint('Verifying token was saved...');
      final verifyToken = prefs.getString(_kLicenseToken);
      if (verifyToken != null && verifyToken.isNotEmpty) {
        debugPrint('✅ Token verification successful - token is in storage');
      } else {
        debugPrint('❌ ERROR: Token verification failed - token not found after saving!');
      }

      // Step 4: Activate license with token
      if (mounted) {
        // Update loading dialog text
        Navigator.of(context).pop();
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Activating license...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      final activateResult = await ApiService.activateLicense(licenseValue, tokenString);
      
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (activateResult['success'] == true && activateResult['activated'] == true) {
        // License activated successfully - save to preferences
        final expiryDateStr = activateResult['expiryDate']?.toString() ?? 
                             validateResult['expiryDate']?.toString() ?? '';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kLicenseNumber, licenseValue);
        if (expiryDateStr.isNotEmpty) {
          await prefs.setString(_kLicenseExpiryDate, expiryDateStr);
        }
        await prefs.setBool(_kLicenseActivated, true);
        // Token was already saved after validation, but ensure it's still there
        await prefs.setString(_kLicenseToken, tokenString);
        debugPrint('✅ Token confirmed saved after activation');
        debugPrint('Final token verification...');
        final finalToken = prefs.getString(_kLicenseToken);
        if (finalToken != null && finalToken.isNotEmpty) {
          debugPrint('✅ Final verification: Token exists in storage (${finalToken.substring(0, 20)}...)');
        } else {
          debugPrint('❌ CRITICAL: Token missing after activation completion!');
        }
        
        setState(() {
          _isLicenseActivated = true;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('License activated successfully. Please configure sync settings below and click Save.'),
              duration: Duration(seconds: 4),
              backgroundColor: Colors.green,
            ),
          );
          
          // License is activated, user can now configure sync settings on the screen
          // No need for dialog - settings are visible on the same screen
        }
      } else {
        // License activation failed, but token is already saved, so API calls should still work
        final errorMessage = activateResult['message'] ?? 'License activation failed';
        debugPrint('Activation failed, but token is saved: $errorMessage');
        
        // Still mark as activated if we have a valid token
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kLicenseActivated, true);
        await prefs.setString(_kLicenseNumber, licenseValue);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Warning: $errorMessage. But license validation token is saved.'),
              duration: const Duration(seconds: 4),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() {
            _isLicenseActivated = true;
          });
        }
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveAll() async {
    // Validate that license is activated
    if (!_isLicenseActivated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please activate your license first before saving settings.'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate sync type is selected
    if (_syncType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a sync type (online or offline).'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate storage location is selected
    if (_storageLocation.isEmpty || _storageLocation == 'Not selected') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a storage location for books.'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Save settings
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSyncType, _syncType);
    await prefs.setString(_kStorageLocation, _storageLocation);
    
    if (mounted) {
      // Navigate to sync screen instead of home
      Navigator.pushReplacementNamed(context, AppRoutes.sync);
    }
  }

  Future<void> _reset() async {
    debugPrint('🔄 Resetting all settings...');
    final prefs = await SharedPreferences.getInstance();
    
    // Check if token exists before clearing
    final tokenBefore = prefs.getString(_kLicenseToken);
    debugPrint('Token before reset: ${tokenBefore != null ? (tokenBefore.substring(0, 20) + '...') : 'null'}');
    
    // Clear SharedPreferences
    await prefs.remove(_kLicenseNumber);
    await prefs.remove(_kLicenseActivated);
    await prefs.remove(_kLicenseExpiryDate);
    await prefs.remove(_kLicenseToken); // Clear the authorization token
    await prefs.remove(_kSyncType);
    await prefs.remove(_kStorageLocation);
    await prefs.remove(_kSyncCompleted);
    
    // Clear local database (all books)
    try {
      final deletedCount = await DatabaseService.clearAllBooks();
      debugPrint('✅ Cleared $deletedCount books from local database');
    } catch (e) {
      debugPrint('❌ Error clearing database: $e');
    }
    
    // Verify token was cleared
    final tokenAfter = prefs.getString(_kLicenseToken);
    if (tokenAfter == null) {
      debugPrint('✅ Token successfully cleared from storage');
    } else {
      debugPrint('❌ WARNING: Token still exists after reset!');
    }
    
    setState(() {
      _licenseController.text = '';
      _isLicenseActivated = false;
      _syncType = 'online';
      _storageLocation = 'Not selected';
    });
    
    debugPrint('✅ All settings and local database reset to default');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings and local database reset to default (including authorization token)'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Shows configuration dialog after license activation
  /// Asks user to select sync type and storage location
  Future<void> _showConfigurationDialog() async {
    String? selectedSyncType = _syncType;
    String? selectedLocation = _storageLocation != 'Not selected' ? _storageLocation : null;
    bool isConfigComplete = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Configure Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Please configure your sync settings:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 20),
                    
                    // Sync Type Selection
                    const Text(
                      'Select Sync Type:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedSyncType,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.sync),
                      ),
                      items: _syncTypes.map((String type) {
                        return DropdownMenuItem<String>(
                          value: type,
                          child: Text(type == 'online' ? 'Online' : 'From External'),
                        );
                      }).toList(),
                      onChanged: (String? value) {
                        setDialogState(() {
                          selectedSyncType = value;
                          _checkConfigComplete(selectedSyncType, selectedLocation, (complete) {
                            isConfigComplete = complete;
                          });
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    
                    // Storage Location Selection
                    const Text(
                      'Select Storage Location:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final String? location = await Navigator.of(context).push<String>(
                          MaterialPageRoute(
                            builder: (context) => FileBrowser(
                              initialPath: selectedLocation,
                              selectDirectory: true,
                              title: 'Select Storage Location',
                            ),
                          ),
                        );
                        
                        if (location != null) {
                          setDialogState(() {
                            selectedLocation = location;
                            _checkConfigComplete(selectedSyncType, selectedLocation, (complete) {
                              isConfigComplete = complete;
                            });
                          });
                        }
                      },
                      icon: const Icon(Icons.folder_open),
                      label: Text(selectedLocation ?? 'Select Folder'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                    if (selectedLocation != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        selectedLocation!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                // Remove Cancel button - user must complete configuration
                // TextButton(
                //   onPressed: () {
                //     Navigator.of(context).pop();
                //   },
                //   child: const Text('Cancel'),
                // ),
                ElevatedButton(
                  onPressed: (selectedSyncType != null && 
                              selectedLocation != null && 
                              selectedLocation!.isNotEmpty)
                      ? () {
                          setState(() {
                            _syncType = selectedSyncType!;
                            _storageLocation = selectedLocation!;
                          });
                          Navigator.of(context).pop();
                          
                          // Save settings and proceed to sync
                          _saveAndProceedToSync();
                        }
                      : null,
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _checkConfigComplete(String? syncType, String? location, Function(bool) callback) {
    callback(syncType != null && 
             location != null && 
             location.isNotEmpty && 
             location != 'Not selected');
  }

  /// Saves settings and navigates to sync screen
  Future<void> _saveAndProceedToSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSyncType, _syncType);
    await prefs.setString(_kStorageLocation, _storageLocation);
    // Mark sync as not completed yet
    await prefs.setBool(_kSyncCompleted, false);
    
    if (mounted) {
      // Navigate to sync screen - this will replace the current route
      // So user cannot go back to settings without completing sync
      Navigator.pushReplacementNamed(context, AppRoutes.sync);
    }
  }

  Future<void> _pickStorageLocation() async {
    try {
      // Request storage permissions first
      final hasPermission = await PermissionHelper.hasStoragePermissions();
      if (!hasPermission) {
        final granted = await PermissionHelper.requestStoragePermissions();
        if (!granted) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Permission Required'),
                content: const Text(
                  'Storage permission is required to select a folder. Please grant permission in app settings.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await PermissionHelper.openAppSettings();
                    },
                    child: const Text('Open Settings'),
                  ),
                ],
              ),
            );
          }
          return;
        }
      }

      // Use custom file browser for better TV compatibility
      final String? selectedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => FileBrowser(
            initialPath: _storageLocation != 'Not selected' ? _storageLocation : null,
            selectDirectory: true,
            title: 'Select Storage Location',
          ),
        ),
      );

      if (selectedPath != null && selectedPath.isNotEmpty) {
        setState(() {
          _storageLocation = selectedPath;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Storage location selected: ${selectedPath.split('/').last}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('File browser error: $e');
      // Fallback to manual input if file browser fails
      if (mounted) {
        _showManualPathInput();
      }
    }
  }

  void _showManualPathInput() {
    final TextEditingController pathController = TextEditingController(
      text: _storageLocation != 'Not selected' ? _storageLocation : '',
    );
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Storage Path'),
        content: TextField(
          controller: pathController,
          decoration: const InputDecoration(
            labelText: 'Folder Path',
            hintText: '/storage/XXXX-XXXX/books',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final path = pathController.text.trim();
              if (path.isNotEmpty) {
                setState(() {
                  _storageLocation = path;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Storage location updated'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<String> _getExpiryDate() async {
    final prefs = await SharedPreferences.getInstance();
    final expiryDateStr = prefs.getString(_kLicenseExpiryDate) ?? '';
    if (expiryDateStr.isNotEmpty) {
      try {
        final expiryDate = DateTime.parse(expiryDateStr);
        return '${expiryDate.year}-${expiryDate.month.toString().padLeft(2, '0')}-${expiryDate.day.toString().padLeft(2, '0')}';
      } catch (e) {
        return 'Invalid date';
      }
    }
    return 'Not set';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // License Number Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'License',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _licenseController,
                          focusNode: _licenseFocusNode,
                          enabled: !_isLicenseActivated,
                          maxLength: 24,
                          decoration: InputDecoration(
                            labelText: 'License Number',
                            hintText: 'Enter your license number',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.vpn_key),
                            suffixIcon: _isLicenseActivated
                                ? const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                  )
                                : null,
                            counterText: '',
                          ),
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) {
                            if (!_isLicenseActivated) {
                              _activateButtonFocusNode.requestFocus();
                            }
                          },
                        ),
                      ),
                      if (!_isLicenseActivated) ...[
                        const SizedBox(width: 12),
                        Focus(
                          focusNode: _activateButtonFocusNode,
                          skipTraversal: false,
                          child: ElevatedButton.icon(
                            onPressed: _activateLicense,
                            icon: const Icon(Icons.verified),
                            label: const Text('Activate'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                            ),
                            autofocus: false,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_isLicenseActivated) ...[
                    const SizedBox(height: 16),
                    FutureBuilder<String>(
                      future: _getExpiryDate(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 20, color: Colors.grey),
                                const SizedBox(width: 12),
                                Text(
                                  'Expiry Date: ${snapshot.data}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Sync Type Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sync Type',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _syncType,
                    decoration: const InputDecoration(
                      labelText: 'Select sync type',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.sync),
                    ),
                    items: _syncTypes.map((String type) {
                      return DropdownMenuItem<String>(
                        value: type,
                        child: Text(type),
                      );
                    }).toList(),
                    onChanged: _isLicenseActivated
                        ? (String? value) {
                            if (value != null) {
                              setState(() => _syncType = value);
                            }
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Storage Location Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Storage Location',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isLicenseActivated ? _pickStorageLocation : null,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Select Folder'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                  if (!_isLicenseActivated)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Please activate license first',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder, size: 20, color: Colors.grey),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _storageLocation,
                            style: TextStyle(
                              fontSize: 14,
                              color: _storageLocation == 'Not selected'
                                  ? Colors.grey.shade600
                                  : Colors.black87,
                              fontStyle: _storageLocation == 'Not selected'
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saveAll,
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

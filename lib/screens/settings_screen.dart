import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../routes.dart';
import '../widgets/file_browser.dart';
import '../widgets/license_keyboard.dart';
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
  static const _kTVCursorEnabled = 'tv_cursor_enabled';

  final TextEditingController _licenseController = TextEditingController();
  final FocusNode _licenseFocusNode = FocusNode();
  final FocusNode _activateButtonFocusNode = FocusNode();
  bool _isLicenseActivated = false;
  String _syncType = 'online';
  String _storageLocation = 'Not selected';
  bool _tvCursorEnabled = true;
  /// On Android: custom keyboard hidden until user taps license field
  bool _showLicenseKeyboard = false;

  @override
  void initState() {
    super.initState();
    _licenseFocusNode.addListener(_onLicenseFocusChange);
    // Defer load so push completes and any prior teardown can settle (reduces random crash)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 80));
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _licenseFocusNode.removeListener(_onLicenseFocusChange);
    _licenseController.dispose();
    _licenseFocusNode.dispose();
    _activateButtonFocusNode.dispose();
    super.dispose();
  }

  void _onLicenseFocusChange() {
    if (_licenseFocusNode.hasFocus &&
        Platform.isAndroid &&
        !_isLicenseActivated &&
        mounted) {
      setState(() => _showLicenseKeyboard = true);
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final tvCursor = prefs.getBool(_kTVCursorEnabled) ?? Platform.isAndroid;
    setState(() {
      _licenseController.text = prefs.getString(_kLicenseNumber) ?? 'CLA-CL252-S71-UF4H021275';
      _isLicenseActivated = prefs.getBool(_kLicenseActivated) ?? false;
      _syncType = prefs.getString(_kSyncType) ?? 'online';
      _storageLocation = prefs.getString(_kStorageLocation) ?? 'Not selected';
      _tvCursorEnabled = tvCursor;
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
        
        // License validation failed - handle specific error cases
        final errorMessage = (validateResult['message'] ?? 'License validation failed').toString().toLowerCase();
        String userMessage;
        if (errorMessage.contains('deleted') || errorMessage.contains('not found') || errorMessage.contains('invalid license')) {
          userMessage = 'License key not found or has been deleted. Please contact support.';
        } else if (errorMessage.contains('already used') || errorMessage.contains('already activated') || errorMessage.contains('device limit')) {
          userMessage = 'This license has already been used. Reset does not allow reusing the same license on this device.';
        } else {
          userMessage = validateResult['message'] ?? 'License validation failed';
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(userMessage),
              duration: const Duration(seconds: 4),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Step 2: Get token from validation response
      final token = validateResult['token'];
      
      if (token == null || token.toString().isEmpty) {
        
        // Check if we have a stored token from previous activation
        final prefs = await SharedPreferences.getInstance();
        final existingToken = prefs.getString(_kLicenseToken);
        if (existingToken != null && existingToken.isNotEmpty) {
          // Continue with activation using existing token
        } else {
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
      final verifyToken = prefs.getString(_kLicenseToken);
      if (verifyToken != null && verifyToken.isNotEmpty) {
      } else {
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
        final finalToken = prefs.getString(_kLicenseToken);
        if (finalToken != null && finalToken.isNotEmpty) {
        } else {
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
        // License activation failed - show friendly message by error type
        final errorMessage = (activateResult['message'] ?? 'License activation failed').toString().toLowerCase();
        final isDeletedOrNotFound = errorMessage.contains('deleted') || errorMessage.contains('not found');
        final isAlreadyUsed = errorMessage.contains('already used') ||
            errorMessage.contains('already activated') ||
            errorMessage.contains('device limit');
        
        if (isDeletedOrNotFound) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('License key not found or has been deleted. Please contact support.'),
                duration: Duration(seconds: 4),
                backgroundColor: Colors.red,
              ),
            );
            setState(() {
              _isLicenseActivated = false;
            });
          }
        } else if (isAlreadyUsed) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This license has already been used on this device.'),
                duration: Duration(seconds: 4),
                backgroundColor: Colors.red,
              ),
            );
            setState(() {
              _isLicenseActivated = false;
            });
          }
        } else {
          // Other activation failure - still try to use token if saved
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_kLicenseActivated, true);
          await prefs.setString(_kLicenseNumber, licenseValue);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Warning: ${activateResult['message'] ?? 'License activation failed'}. But license validation token is saved.'),
                duration: const Duration(seconds: 4),
                backgroundColor: Colors.orange,
              ),
            );
            setState(() {
              _isLicenseActivated = true;
            });
          }
        }
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
            duration: Duration(seconds: 4),
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
    await _clearBooksIfStorageChanged(prefs);
    await prefs.setString(_kSyncType, _syncType);
    await prefs.setString(_kStorageLocation, _storageLocation);
    
    if (mounted) {
      // Navigate to sync screen instead of home
      Navigator.pushReplacementNamed(context, AppRoutes.sync);
    }
  }

  Future<void> _reset() async {
    final prefs = await SharedPreferences.getInstance();
    final storageLocation = prefs.getString(_kStorageLocation);
    final hasStorage = storageLocation != null &&
        storageLocation.isNotEmpty &&
        storageLocation != 'Not selected';

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Reset'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will permanently delete:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text('• License and activation data'),
              const Text('• All app settings'),
              const Text('• Local book database'),
              const Text('• All caches (images, decrypted books, temp files)'),
              if (hasStorage) ...[
                const SizedBox(height: 8),
                Text(
                  '• All downloaded books and thumbnails from:\n$storageLocation',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'This action cannot be undone. Are you sure?',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset & Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;


    // 1. Delete books from storage location (courses and books folders)
    if (hasStorage) {
      try {
        final coursesDir = Directory(path.join(storageLocation, 'courses'));
        if (await coursesDir.exists()) {
          await coursesDir.delete(recursive: true);
        }
        final booksDir = Directory(path.join(storageLocation, 'books'));
        if (await booksDir.exists()) {
          await booksDir.delete(recursive: true);
        }
        final thumbnailsDir = Directory(path.join(storageLocation, 'thumbnails'));
        if (await thumbnailsDir.exists()) {
          await thumbnailsDir.delete(recursive: true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not delete books from storage: $e'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }

    // 2. Clear local database and delete DB file
    try {
      await DatabaseService.clearAllBooks();
      await DatabaseService.close();
      final docDir = await getApplicationDocumentsDirectory();
      final dbFile = File(path.join(docDir.path, 'books.db'));
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
    } catch (e) { /* ignore */ }

    // 3. Clear all caches and WebView storage
    try {
      await DefaultCacheManager().emptyCache();
    } catch (e) { /* ignore */ }
    try {
      await WebViewCookieManager().clearCookies();
    } catch (e) { /* ignore */ }
    try {
      final tempDir = await getTemporaryDirectory();
      for (final dirName in ['decrypted_books', 'extracted_books']) {
        final d = Directory(path.join(tempDir.path, dirName));
        if (await d.exists()) {
          await d.delete(recursive: true);
        }
      }
      final cacheDir = await getApplicationCacheDirectory();
      if (await cacheDir.exists()) {
        await for (final entity in cacheDir.list()) {
          try {
            if (entity is Directory) {
              await entity.delete(recursive: true);
            } else if (entity is File) {
              await entity.delete();
            }
          } catch (_) {}
        }
      }
      final supportDir = await getApplicationSupportDirectory();
      if (await supportDir.exists()) {
        await for (final entity in supportDir.list()) {
          try {
            if (entity is Directory) {
              await entity.delete(recursive: true);
            } else if (entity is File) {
              await entity.delete();
            }
          } catch (_) {}
        }
      }
      final docsDir = await getApplicationDocumentsDirectory();
      if (await docsDir.exists()) {
        await for (final entity in docsDir.list()) {
          try {
            if (entity is Directory) {
              await entity.delete(recursive: true);
            } else if (entity is File) {
              await entity.delete();
            }
          } catch (_) {}
        }
      }
      if (Platform.isWindows) {
        final localAppData = Platform.environment['LOCALAPPDATA'];
        final roamingAppData = Platform.environment['APPDATA'];
        final candidates = <String>[
          if (localAppData != null) path.join(localAppData, 'BurlingtonEnglish'),
          if (localAppData != null) path.join(localAppData, 'com.liqvid.tv_app_books'),
          if (localAppData != null) path.join(localAppData, 'com.example', 'BurlingtonEnglish'),
          if (roamingAppData != null) path.join(roamingAppData, 'BurlingtonEnglish'),
          if (roamingAppData != null) path.join(roamingAppData, 'com.liqvid.tv_app_books'),
        ];
        for (final p in candidates) {
          try {
            final d = Directory(p);
            if (await d.exists()) {
              await d.delete(recursive: true);
            }
          } catch (_) {}
        }
        if (localAppData != null) {
          final tempDir = Directory(path.join(localAppData, 'Temp'));
          if (await tempDir.exists()) {
            await for (final entity in tempDir.list()) {
              if (entity is Directory &&
                  path.basename(entity.path).startsWith('tv_app_books')) {
                try {
                  await entity.delete(recursive: true);
                } catch (_) {}
              }
            }
          }
        }
      }
    } catch (e) { /* ignore */ }

    // 4. Clear SharedPreferences (all app data)
    await prefs.clear();

    if (!mounted) return;
    setState(() {
      _licenseController.text = '';
      _isLicenseActivated = false;
      _syncType = 'online';
      _storageLocation = 'Not selected';
      _tvCursorEnabled = Platform.isAndroid;
    });


    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasStorage
                ? 'Reset complete. All data, caches, and downloaded books have been deleted.'
                : 'Reset complete. All data and caches have been deleted.',
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Shows configuration dialog after license activation
  /// Asks user to select storage location (sync is always online)
  Future<void> _showConfigurationDialog() async { // ignore: unused_element
    String? selectedLocation = _storageLocation != 'Not selected' ? _storageLocation : null;

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
                      'Please select a storage location for your books:',
                      style: TextStyle(fontWeight: FontWeight.w600),
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
                        final String? location = await _selectStoragePath(
                          initialPath: selectedLocation,
                        );
                        if (location != null) {
                        setDialogState(() {
                            selectedLocation = location;
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
                ElevatedButton(
                  onPressed: (selectedLocation != null && (selectedLocation?.isNotEmpty ?? false))
                      ? () {
                          setState(() {
                            _syncType = 'online';
                            _storageLocation = selectedLocation!;
                          });
                          Navigator.of(context).pop();
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

  // ignore: unused_element
  void _checkConfigComplete(String? location, Function(bool) callback) {
    callback(location != null &&
             location.isNotEmpty &&
             location != 'Not selected');
  }

  /// Clears books from DB when storage location changes (avoids showing books from old folder)
  Future<void> _clearBooksIfStorageChanged(SharedPreferences prefs) async {
    final oldStorage = prefs.getString(_kStorageLocation);
    final storageChanged = oldStorage != null &&
        oldStorage.isNotEmpty &&
        oldStorage != 'Not selected' &&
        oldStorage != _storageLocation;
    if (storageChanged) {
      try {
        await DatabaseService.clearAllBooks();
      } catch (e) { /* ignore */ }
    }
  }

  /// Saves settings and navigates to sync screen
  Future<void> _saveAndProceedToSync() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearBooksIfStorageChanged(prefs);
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

  /// Returns the default Download folder path for the current platform.
  static String get _defaultDownloadPath {
    if (Platform.isAndroid) {
      return '/storage/emulated/0/Download';
    }
    if (Platform.isWindows) {
      return path.join(Platform.environment['USERPROFILE'] ?? 'C:\\Users', 'Downloads');
    }
    if (Platform.isLinux) {
      return path.join(Platform.environment['HOME'] ?? '/home', 'Downloads');
    }
    return '';
  }

  /// Returns selected folder path, or null. Offers Download folder, browse, and system picker.
  Future<String?> _selectStoragePath({String? initialPath}) async {
    if (!mounted) return null;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Where should books be saved?'),
        content: const Text(
          'Choose the folder where downloaded books will be stored.\n\n'
          '• Downloads – use your device\'s Download folder\n'
          '• Browse – pick any folder (internal storage, USB, etc.)\n'
          '• System picker – use the system folder picker',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
          if (_defaultDownloadPath.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, 'download'),
              child: const Text('Downloads'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'browse'),
            child: const Text('Browse'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'picker'),
            child: const Text('System picker'),
          ),
        ],
      ),
    );
    if (choice == 'download' && _defaultDownloadPath.isNotEmpty) {
      return _defaultDownloadPath;
    }
    if (choice == 'picker') {
      return await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select folder for books',
        initialDirectory: initialPath ?? (Platform.isAndroid ? null : _defaultDownloadPath),
      );
    }
    if (choice == 'browse' && mounted) {
      return await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => FileBrowser(
            initialPath: initialPath,
            selectDirectory: true,
            title: 'Select folder for books',
          ),
        ),
      );
    }
    return null;
  }

  Future<void> _pickStorageLocation() async {
    try {
      // Storage permission only on Android; Windows/Linux can browse without it
      if (!Platform.isWindows && !Platform.isLinux) {
        final hasPermission = await PermissionHelper.hasStoragePermissions();
        if (!hasPermission) {
          final granted = await PermissionHelper.requestStoragePermissions();
          if (!granted) {
            if (mounted) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Storage Access Required'),
                  content: const Text(
                    'To select folders on internal or external storage (including USB drives), '
                    'please grant "All files access" in the next screen.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await PermissionHelper.openAllFilesAccessSettings();
                      },
                      child: const Text('Grant Access'),
                    ),
                  ],
                ),
              );
            }
            return;
          }
        }
      }

      final selectedPath = await _selectStoragePath(
        initialPath: _storageLocation != 'Not selected' ? _storageLocation : null,
      );

      if (selectedPath != null && selectedPath.isNotEmpty) {
        setState(() {
          _storageLocation = selectedPath;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Storage location selected: ${path.basename(selectedPath)}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Decide now so deferred callback doesn't see stale focus
        final shouldUnfocusFirst = _licenseFocusNode.hasFocus;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          if (shouldUnfocusFirst) {
            FocusScope.of(context).unfocus();
          } else {
            Navigator.of(context).pop(true);
          }
        });
      },
      child: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          if (Platform.isAndroid) setState(() => _showLicenseKeyboard = false);
        },
        behavior: HitTestBehavior.opaque,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            title: const Text('WebBooks Settings'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: () {
                if (_licenseFocusNode.hasFocus) {
                  FocusScope.of(context).unfocus();
                } else {
                  Navigator.of(context).pop(true);
                }
              },
            ),
          ),
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
                    'Enter your license number',
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
                          readOnly: Platform.isAndroid && !_isLicenseActivated,
                          maxLength: 24,
                          decoration: InputDecoration(
                            labelText: 'Enter your license number',
                            hintText: Platform.isAndroid && !_isLicenseActivated
                                ? 'Tap to open keyboard'
                                : 'Enter your license number',
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
                  if (Platform.isAndroid &&
                      !_isLicenseActivated &&
                      _showLicenseKeyboard) ...[
                    const SizedBox(height: 12),
                    LicenseKeyboard(
                      controller: _licenseController,
                      maxLength: 24,
                    ),
                  ],
                  // Expiry date display removed per P1 (remove from installer/settings)
                  if (_isLicenseActivated) ...[
                    const SizedBox(height: 8),
                  ],
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
                  if (Platform.isAndroid) ...[
                    const SizedBox(height: 8),
                    FutureBuilder<bool>(
                      future: PermissionHelper.hasStoragePermissions(),
                      builder: (context, snap) {
                        if (snap.data == true) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final ok = await PermissionHelper.requestStoragePermissions();
                              if (mounted) {
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(ok ? 'Storage access granted' : 'Please grant access in Settings'),
                                  duration: const Duration(seconds: 2),
                                ));
                              }
                            },
                            icon: const Icon(Icons.security),
                            label: const Text('Grant storage access (internal + external)'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange.shade800,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
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
          if (Platform.isAndroid) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reading / TV',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Show TV navigation cursor (D-pad overlay)',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                        Switch(
                          value: _tvCursorEnabled,
                          onChanged: (bool value) async {
                            setState(() => _tvCursorEnabled = value);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool(_kTVCursorEnabled, value);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
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
        ), // Scaffold
      ), // GestureDetector
    ); // PopScope
  }
}

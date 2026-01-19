import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../routes.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _kLicenseNumber = 'licenseNumber';
  static const _kLicenseActivated = 'licenseActivated';
  static const _kLicenseExpiryDate = 'licenseExpiryDate';
  static const _kSyncType = 'syncType';
  static const _kStorageLocation = 'storageLocation';

  final TextEditingController _licenseController = TextEditingController();
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
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _licenseController.text = prefs.getString(_kLicenseNumber) ?? '';
      _isLicenseActivated = prefs.getBool(_kLicenseActivated) ?? false;
      _syncType = prefs.getString(_kSyncType) ?? 'online';
      _storageLocation = prefs.getString(_kStorageLocation) ?? 'Not selected';
    });
  }

  Future<void> _activateLicense() async {
    final licenseNumber = _licenseController.text.trim();
    
    if (licenseNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a license number'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    if (licenseNumber.length > 16) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('License number must be 16 characters or less'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    // Auto-set expiry date to 1 year from now
    final expiryDate = DateTime.now().add(const Duration(days: 365));
    final expiryDateStr = '${expiryDate.year}-${expiryDate.month.toString().padLeft(2, '0')}-${expiryDate.day.toString().padLeft(2, '0')}';
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLicenseNumber, licenseNumber);
    await prefs.setString(_kLicenseExpiryDate, expiryDateStr);
    await prefs.setBool(_kLicenseActivated, true);
    
    setState(() {
      _isLicenseActivated = true;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('License activated successfully'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );
      
      // Navigate back to home screen after activation
      // Pass true to indicate license was activated
      // Home screen will automatically refresh and show books
      Navigator.pop(context, true);
    }
  }

  Future<void> _saveAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSyncType, _syncType);
    await prefs.setString(_kStorageLocation, _storageLocation);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved successfully'),
          duration: Duration(seconds: 2),
        ),
      );
      
      // Navigate back to home screen after saving
      // Pass true to indicate settings were saved
      Navigator.pop(context, true);
    }
  }

  Future<void> _reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLicenseNumber);
    await prefs.remove(_kLicenseActivated);
    await prefs.remove(_kLicenseExpiryDate);
    await prefs.remove(_kSyncType);
    await prefs.remove(_kStorageLocation);
    
    setState(() {
      _licenseController.text = '';
      _isLicenseActivated = false;
      _syncType = 'online';
      _storageLocation = 'Not selected';
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings reset to default'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _pickStorageLocation() async {
    try {
      // For Android TV, file_picker might not work well
      // Try directory picker first
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select folder to store books',
      );

      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        setState(() {
          _storageLocation = selectedDirectory;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Storage location selected: ${selectedDirectory.split('/').last}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // If file picker doesn't work, show manual input dialog for TV
        _showManualPathInput();
      }
    } catch (e) {
      debugPrint('File picker error: $e');
      // On Android TV, file picker might not be available
      // Show manual path input as fallback
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
                          enabled: !_isLicenseActivated,
                          maxLength: 16,
                          decoration: InputDecoration(
                            labelText: 'License Number',
                            hintText: 'Enter your license number (max 16 chars)',
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
                        ),
                      ),
                      if (!_isLicenseActivated) ...[
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _activateLicense,
                          icon: const Icon(Icons.verified),
                          label: const Text('Activate'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
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
                    onChanged: (String? value) {
                      if (value != null) {
                        setState(() => _syncType = value);
                      }
                    },
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
                    onPressed: _pickStorageLocation,
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

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../utils/permission_helper.dart';

/// Represents a storage location (internal storage or USB drive)
class StorageLocation {
  final String path;
  final String name;
  final bool isInternal;
  final String? displayPath;

  StorageLocation({
    required this.path,
    required this.name,
    this.isInternal = false,
    this.displayPath,
  });
}

/// A TV-friendly file browser widget for selecting directories or files
class FileBrowser extends StatefulWidget {
  final String? initialPath;
  final bool selectDirectory; // true for folder selection, false for file selection
  final List<String>? allowedExtensions; // e.g., ['.zip', '.html'] - null for all files
  final String? title;

  const FileBrowser({
    super.key,
    this.initialPath,
    this.selectDirectory = true,
    this.allowedExtensions,
    this.title,
  });

  @override
  State<FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<FileBrowser> with WidgetsBindingObserver {
  String? _currentPath;
  List<FileSystemEntity> _items = [];
  bool _isLoading = false;
  String? _error;
  bool _showStorageLocations = false;
  List<StorageLocation> _storageLocations = [];
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAndLoad();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    // User may have returned from Settings after granting "All files access"
    if (Platform.isAndroid && _permissionDenied) {
      PermissionHelper.hasStoragePermissions().then((granted) {
        if (granted && mounted) {
          setState(() {
            _permissionDenied = false;
            _error = null;
            _isLoading = true;
          });
          _initializeAndLoad();
        }
      });
    }
  }

  /// Get list of all available storage locations (internal + USB drives)
  /// Yields control periodically to avoid blocking main thread
  Future<List<StorageLocation>> _getAllStorageLocations() async {
    final locations = <StorageLocation>[];

    // Windows: list all drive letters (C:\, D:\, ...) for folder selection
    if (Platform.isWindows) {
      for (final letter in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z']) {
        final drivePath = '$letter:\\';
        try {
          final dir = Directory(drivePath);
          if (await dir.exists()) {
            locations.add(StorageLocation(
              path: drivePath,
              name: 'Drive $letter:',
              isInternal: letter == 'C',
              displayPath: drivePath,
            ));
          }
        } catch (_) {}
      }
      return locations;
    }

    // Linux: /, /home, /mnt, /media, /run/media (USB drives on modern distros)
    if (Platform.isLinux) {
      final linuxRoots = ['/', '/home', '/mnt', '/media', '/run/media'];
      for (final root in linuxRoots) {
        try {
          final dir = Directory(root);
          if (await dir.exists()) {
            try {
              await dir.list().first.timeout(const Duration(milliseconds: 500));
              locations.add(StorageLocation(
                path: root,
                name: root == '/' ? 'Root' : root == '/run/media' ? 'External drives (USB)' : path.basename(root),
                isInternal: root == '/home',
                displayPath: root,
              ));
            } catch (_) {}
          }
        } catch (_) {}
      }
      if (locations.isNotEmpty) {
        return locations;
      }
    }

    // Android: internal storage + external SD + USB drives
    final internalPaths = [
      '/storage/emulated/0',
      '/sdcard',
      '/mnt/sdcard',
    ];
    
    String? addedInternalPath;
    for (final internalPath in internalPaths) {
      try {
        final dir = Directory(internalPath);
        if (await dir.exists()) {
          try {
            await dir.list().first.timeout(const Duration(milliseconds: 500));
            locations.add(StorageLocation(
              path: internalPath,
              name: 'Internal Storage',
              isInternal: true,
              displayPath: internalPath,
            ));
            addedInternalPath = internalPath;
            break; // Only add one internal storage path
          } catch (e) {
            continue;
          }
        }
      } catch (e) {
        continue;
      }
    }

    // Android: add Download folder so it's easy to select (standard path for downloads)
    if (Platform.isAndroid && addedInternalPath != null) {
      final downloadPaths = [
        path.join(addedInternalPath, 'Download'),
        '/storage/emulated/0/Download',
        '/sdcard/Download',
      ];
      for (final downloadPath in downloadPaths) {
        try {
          final dir = Directory(downloadPath);
          if (await dir.exists()) {
            try {
              await dir.list().first.timeout(const Duration(milliseconds: 300));
              if (!locations.any((l) => l.path == downloadPath)) {
                locations.add(StorageLocation(
                  path: downloadPath,
                  name: 'Download folder',
                  isInternal: true,
                  displayPath: downloadPath,
                ));
              }
              break;
            } catch (_) {}
          }
        } catch (_) {}
      }
    }

    // Check /mnt/expand for adopted storage (external SD formatted as internal)
    try {
      final expandDir = Directory('/mnt/expand');
      if (await expandDir.exists()) {
        await for (final entity in expandDir.list()) {
          if (entity is Directory) {
            try {
              await entity.list().first.timeout(const Duration(milliseconds: 500));
              final p = entity.path;
              if (!locations.any((l) => l.path == p)) {
                locations.add(StorageLocation(
                  path: p,
                  name: 'External storage (${path.basename(p)})',
                  isInternal: false,
                  displayPath: p,
                ));
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    // Check /mnt/media_rw for USB drives (common on Android TV)
    try {
      final mediaRwDir = Directory('/mnt/media_rw');
      if (await mediaRwDir.exists()) {
        try {
          int count = 0;
          await for (final entity in mediaRwDir.list()) {
            if (count++ % 5 == 0) await Future.delayed(const Duration(milliseconds: 1));
            if (entity is Directory) {
              final dirName = path.basename(entity.path);
              final fullPath = entity.path;
              try {
                await entity.list().first.timeout(const Duration(milliseconds: 500));
                if (!locations.any((loc) => loc.path == fullPath || path.basename(loc.path) == dirName)) {
                  locations.add(StorageLocation(
                    path: fullPath,
                    name: 'USB Drive ($dirName)',
                    isInternal: false,
                    displayPath: fullPath,
                  ));
                }
              } catch (e) { /* ignore */ }
            }
          }
        } catch (e) { /* ignore */ }
      }
    } catch (e) { /* ignore */ }

    // Android TV / OEM-specific USB mount points
    final androidUsbRoots = [
      '/mnt/usb',
      '/mnt/usbdisk',
      '/mnt/usb_storage',
      '/mnt/udisk',
      '/storage/usb0',
      '/storage/usb1',
      '/storage/udisk',
    ];
    for (final root in androidUsbRoots) {
      try {
        final dir = Directory(root);
        if (await dir.exists()) {
          try {
            await dir.list().first.timeout(const Duration(milliseconds: 500));
            if (!locations.any((l) => l.path == root)) {
              locations.add(StorageLocation(
                path: root,
                name: 'External USB ($root)',
                isInternal: false,
                displayPath: root,
              ));
            }
          } catch (_) { /* ignore */ }
          // Also list subdirs (e.g. /mnt/usb/sda1)
          try {
            await for (final entity in dir.list()) {
              if (entity is Directory) {
                final fullPath = entity.path;
                final dirName = path.basename(fullPath);
                try {
                  await entity.list().first.timeout(const Duration(milliseconds: 300));
                  if (!locations.any((l) => l.path == fullPath)) {
                    locations.add(StorageLocation(
                      path: fullPath,
                      name: 'USB Drive ($dirName)',
                      isInternal: false,
                      displayPath: fullPath,
                    ));
                  }
                } catch (_) { /* ignore */ }
              }
            }
          } catch (_) { /* ignore */ }
        }
      } catch (_) { /* ignore */ }
    }
    
    // Check /storage for mounted devices (including USB drives)
    // This is often a symlink to /mnt/media_rw, but let's check anyway
    try {
      final storageDir = Directory('/storage');
      if (await storageDir.exists()) {
        try {
          int count = 0;
          await for (final entity in storageDir.list()) {
            // Yield control periodically to avoid blocking UI
            if (count++ % 5 == 0) {
              await Future.delayed(const Duration(milliseconds: 1));
            }
            
            if (entity is Directory) {
              final dirName = path.basename(entity.path);
              final fullPath = entity.path;
              
              // Skip internal storage (emulated) as we already added it
              if (dirName == 'emulated' || dirName == 'self') {
                continue;
              }
              
              
              // This is likely a USB drive or external storage
              try {
                // Quick test to see if we can access it
                await entity.list().first.timeout(const Duration(milliseconds: 500));
                
                // Check if we already have this path (avoid duplicates)
                final pathExists = locations.any((loc) => loc.path == fullPath || 
                  path.basename(loc.path) == dirName ||
                  (loc.path.contains(dirName) && dirName.length > 3));
                
                if (!pathExists) {
                  locations.add(StorageLocation(
                    path: fullPath,
                    name: dirName.contains('-') ? 'USB Drive ($dirName)' : 'External Storage ($dirName)',
                    isInternal: false,
                    displayPath: fullPath,
                  ));
                }
              } catch (e) {
                continue;
              }
            }
          }
        } catch (e) { /* ignore */ }
      }
    } catch (e) { /* ignore */ }
    
    // On Android, always add "Browse All Storage Devices" first so user can
    // manually navigate to /storage and find USB drives (required in release APK)
    if (Platform.isAndroid) {
      try {
        final storageDir = Directory('/storage');
        if (await storageDir.exists() && !locations.any((l) => l.path == '/storage')) {
          locations.insert(0, StorageLocation(
            path: '/storage',
            name: 'Browse All Storage Devices (USB / SD)',
            isInternal: false,
            displayPath: '/storage',
          ));
        }
      } catch (e) { /* ignore */ }
    } else {
      final hasExternal = locations.any((loc) => !loc.isInternal);
      if (!hasExternal) {
        try {
          final storageDir = Directory('/storage');
          if (await storageDir.exists()) {
            locations.add(StorageLocation(
              path: '/storage',
              name: 'Browse All Storage Devices',
              isInternal: false,
              displayPath: '/storage',
            ));
          }
        } catch (e) { /* ignore */ }
      }
    }
    
    return locations;
  }

  Future<void> _initializeAndLoad() async {
    // Storage permission only on Android; Windows/Linux can browse without it
    if (!Platform.isWindows && !Platform.isLinux) {
      final hasPermission = await PermissionHelper.hasStoragePermissions();
      if (!hasPermission) {
        final granted = await PermissionHelper.requestStoragePermissions();
        if (!granted) {
          if (mounted) {
            setState(() {
              _permissionDenied = true;
              _error = 'Storage permission is required to browse folders (including USB drives). '
                  'Please enable "All files access" in the next screen.';
              _isLoading = false;
            });
          }
          return;
        }
      }
    }

    // Treat "Not selected" like null -> show storage locations first
    var initialPath = widget.initialPath;
    if (initialPath == 'Not selected' || initialPath == null || initialPath.isEmpty) {
      initialPath = null;
    }

    // If no initial path specified, show storage locations view first
    if (initialPath == null) {
      setState(() {
        _isLoading = true;
      });
      
      // Load all available storage locations
      final storageLocations = await _getAllStorageLocations();
      
      setState(() {
        _storageLocations = storageLocations;
        _showStorageLocations = true;
        _isLoading = false;
        _currentPath = 'Storage Locations';
      });
    } else {
      _loadPath(initialPath);
    }
  }

  /// Finds the first accessible storage path, prioritizing USB drives.
  // ignore: unused_element
  Future<String?> _findAccessibleStoragePath() async {
    // First, try to find USB drives in /storage (most common location)
    try {
      final storageDir = Directory('/storage');
      if (await storageDir.exists()) {
        try {
          await for (final entity in storageDir.list()) {
            if (entity is Directory) {
              final dirName = path.basename(entity.path);
              // USB drives typically have format like XXXX-XXXX or a volume name
              // Skip 'emulated' as that's internal storage
              if (dirName != 'emulated' && dirName != 'self') {
                // Try to access this directory
                try {
                  await entity.list().first.timeout(const Duration(milliseconds: 500));
                  return entity.path; // Found a USB drive
                } catch (e) {
                  // Can't access this one, try next
                  continue;
                }
              }
            }
          }
        } catch (e) {
          // Can't list /storage, try other paths
        }
      }
    } catch (e) {
      // /storage doesn't exist or not accessible
    }
    
    // Try /mnt/media_rw for USB drives (alternative location)
    try {
      final mediaRwDir = Directory('/mnt/media_rw');
      if (await mediaRwDir.exists()) {
        try {
          await for (final entity in mediaRwDir.list()) {
            if (entity is Directory) {
              try {
                await entity.list().first.timeout(const Duration(milliseconds: 500));
                return entity.path; // Found a USB drive
              } catch (e) {
                continue;
              }
            }
          }
        } catch (e) {
          // Can't list /mnt/media_rw
        }
      }
    } catch (e) {
      // /mnt/media_rw doesn't exist or not accessible
    }
    
    // Fallback to internal storage paths
    final accessiblePaths = [
      '/storage/emulated/0',
      '/sdcard',
      '/mnt/sdcard',
      '/mnt/media_rw',
      '/storage',
    ];
    
    for (final path in accessiblePaths) {
      try {
        final dir = Directory(path);
        if (await dir.exists()) {
          // Try to list it to ensure we have permission
          await dir.list().first.timeout(const Duration(milliseconds: 500));
          return path;
        }
      } catch (e) {
        // Skip this path if we can't access it
        continue;
      }
    }
    
    // Default fallback
    return '/storage/emulated/0';
  }

  Future<void> _loadPath(String? targetPath) async {
    if (targetPath == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final directory = Directory(targetPath);
      
      if (!await directory.exists()) {
        // Try common Android storage paths that are more accessible
        final commonPaths = [
          '/storage/emulated/0',
          '/sdcard',
          '/mnt/sdcard',
          '/mnt/media_rw',
        ];
        
        String? foundPath;
        for (final commonPath in commonPaths) {
          try {
            final testDir = Directory(commonPath);
            if (await testDir.exists()) {
              // Try to list it to ensure we have permission
              await testDir.list().first.timeout(const Duration(milliseconds: 500));
              foundPath = commonPath;
              break;
            }
          } catch (e) {
            // Skip this path if we can't access it
            continue;
          }
        }
        
        if (foundPath != null) {
          await _loadDirectory(Directory(foundPath));
        } else {
          setState(() {
            _error = 'Directory not found or permission denied: $targetPath\n\nPlease try selecting a different location.';
            _isLoading = false;
          });
        }
        return;
      }

      await _loadDirectory(directory);
    } catch (e) {
      // Check if it's a permission error (Android only; desktop skips permission flow)
      final errorMessage = e.toString().toLowerCase();
      if (!Platform.isWindows && !Platform.isLinux &&
          (errorMessage.contains('permission') || 
           errorMessage.contains('denied') ||
           errorMessage.contains('eacces'))) {
        final granted = await PermissionHelper.requestStoragePermissions();
        if (!granted) {
          setState(() {
            _error = 'Permission denied. Unable to access this folder.\n\nPlease grant storage permission in app settings.';
            _isLoading = false;
          });
          return;
        }
        await _loadPath(targetPath);
        return;
      }
      if (errorMessage.contains('pathaccessexception') ||
                 errorMessage.contains('directory listing failed')) {
        // Specific handling for directory listing permission errors
        setState(() {
          _error = 'Permission denied: Cannot access "$targetPath".\n\nPlease try:\n1. Grant storage permission in app settings\n2. Navigate to /storage/emulated/0 or /sdcard instead';
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Error loading path: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadDirectory(Directory directory) async {
    try {
      final items = <FileSystemEntity>[];
      
      // Add parent directory option (except at root or /storage which might not be accessible)
      final currentPath = directory.path;
      final isWindowsDriveRoot = Platform.isWindows &&
          currentPath.length == 3 &&
          currentPath[1] == ':' &&
          currentPath.endsWith('\\') &&
          currentPath[0].toUpperCase().codeUnitAt(0) >= 0x41 &&
          currentPath[0].toUpperCase().codeUnitAt(0) <= 0x5A;

      // Don't add parent for root storage dirs or Windows drive roots; use "All Storage" to switch drives
      if (currentPath == '/storage' || currentPath == '/mnt' || currentPath == '/mnt/media_rw' || isWindowsDriveRoot) {
        // No parent row
      } else if (currentPath != '/') {
        // Only add parent if we're not at the top level
        final parentPath = path.dirname(currentPath);
        if (parentPath != currentPath && parentPath != '.' && parentPath != '/storage' && parentPath != '/mnt') {
          items.add(Directory(parentPath));
        } else if (parentPath == '/storage' || parentPath == '/mnt' || parentPath == '/mnt/media_rw') {
          // Always allow navigating back to storage root to see all devices
          items.add(Directory(parentPath));
        }
      }

      // List directory contents with error handling
      await for (final entity in directory.list()) {
        if (entity is Directory) {
          // When in /storage or /mnt/media_rw, show all directories (including USB drives)
          // Filter out some system directories that are not useful
          final dirName = path.basename(entity.path);
          if (dirName != 'self' && dirName != 'obb') {
            items.add(entity);
          }
        } else if (entity is File) {
          // Filter by extension if specified
          if (widget.selectDirectory) {
            // Skip files when selecting directories
            continue;
          }
          
          if (widget.allowedExtensions != null) {
            final ext = path.extension(entity.path).toLowerCase();
            if (!widget.allowedExtensions!.contains(ext)) {
              continue;
            }
          }
          
          items.add(entity);
        }
      }

      // Sort: directories first, then files, both alphabetically
      items.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return path.basename(a.path).toLowerCase().compareTo(
               path.basename(b.path).toLowerCase());
      });

      setState(() {
        _currentPath = directory.path;
        _items = items;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('permission') || 
          errorMessage.contains('denied') ||
          errorMessage.contains('eacces') ||
          errorMessage.contains('pathaccessexception') ||
          errorMessage.contains('directory listing failed')) {
        setState(() {
          _error = 'Permission denied: Cannot access "$directory.path".\n\nPlease try navigating to a different folder or grant storage permission in app settings.';
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Error reading directory: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _onItemSelected(FileSystemEntity entity) {
    if (entity is Directory) {
      // Navigate into directory
      setState(() {
        _showStorageLocations = false;
      });
      _loadPath(entity.path);
    } else if (entity is File) {
      // File selected - return the file path
      Navigator.pop(context, entity.path);
    }
  }

  void _selectCurrentDirectory() {
    if (_currentPath != null) {
      Navigator.pop(context, _currentPath);
    }
  }

  Widget _buildStorageLocationsView() {
    if (_storageLocations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.storage, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'No storage locations found',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _refreshStorageLocations,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
              if (Platform.isAndroid) ...[
                const SizedBox(height: 12),
                Text(
                  'If USB does not appear, tap "Browse All Storage (USB / SD)" and open the USB folder, or enable All files access in app settings.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _storageLocations.length,
      itemBuilder: (context, index) {
        final location = _storageLocations[index];
        return ListTile(
          leading: Icon(
            location.isInternal ? Icons.phone_android : Icons.usb,
            color: location.isInternal ? Colors.blue : Colors.orange,
            size: 32,
          ),
          title: Text(
            location.name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            location.displayPath ?? location.path,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            setState(() {
              _showStorageLocations = false;
            });
            _loadPath(location.path);
          },
        );
      },
    );
  }

  Future<void> _refreshStorageLocations() async {
    setState(() => _isLoading = true);
    final storageLocations = await _getAllStorageLocations();
    if (mounted) {
      setState(() {
        _storageLocations = storageLocations;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? (widget.selectDirectory ? 'Select Folder' : 'Select File')),
        actions: [
          if (_showStorageLocations && Platform.isAndroid)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh storage list (plug in USB then tap)',
              onPressed: _isLoading ? null : _refreshStorageLocations,
            ),
        ],
      ),
      body: Column(
        children: [
          // Current path display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade200,
            child: Row(
              children: [
                const Icon(Icons.folder, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentPath ?? 'Loading...',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Add a button to navigate back to storage locations view
                if (!_showStorageLocations && _currentPath != null && _currentPath != 'Storage Locations')
                  TextButton.icon(
                    onPressed: () async {
                      setState(() {
                        _isLoading = true;
                      });
                      final storageLocations = await _getAllStorageLocations();
                      setState(() {
                        _storageLocations = storageLocations;
                        _showStorageLocations = true;
                        _currentPath = 'Storage Locations';
                        _isLoading = false;
                      });
                    },
                    icon: const Icon(Icons.storage, size: 18),
                    label: const Text('All Storage'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ),

          // Content area
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _showStorageLocations
                    ? _buildStorageLocationsView()
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                                  const SizedBox(height: 16),
                                  Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  const SizedBox(height: 24),
                                  if (Platform.isAndroid && _permissionDenied) ...[
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        await PermissionHelper.openAllFilesAccessSettings();
                                        // Re-check after a short delay (user may have granted)
                                        await Future.delayed(const Duration(milliseconds: 500));
                                        if (mounted) {
                                          final granted = await PermissionHelper.hasStoragePermissions();
                                          if (granted) {
                                            setState(() {
                                              _permissionDenied = false;
                                              _error = null;
                                              _isLoading = true;
                                            });
                                            _initializeAndLoad();
                                          }
                                        }
                                      },
                                      icon: const Icon(Icons.settings),
                                      label: const Text('Open settings – Allow all files (USB)'),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  ElevatedButton.icon(
                                    onPressed: () => _loadPath(_currentPath),
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _items.isEmpty
                            ? const Center(
                                child: Text(
                                  'No items found',
                                  style: TextStyle(fontSize: 16, color: Colors.grey),
                                ),
                              )
                            : ListView.builder(
                                itemCount: _items.length,
                                itemBuilder: (context, index) {
                                  final item = _items[index];
                                  final isDirectory = item is Directory;
                                  final isParent = index == 0 && 
                                                 _currentPath != '/' && 
                                                 _currentPath != '/storage' &&
                                                 _currentPath != 'Storage Locations' &&
                                                 item is Directory;
                                  
                                  // Detect if this is a USB drive or external storage
                                  final itemPath = item.path;
                                  final itemName = path.basename(itemPath);
                                  final isUsbDrive = (itemName.contains('-') || 
                                                      _currentPath == '/storage' || 
                                                      _currentPath == '/mnt/media_rw') &&
                                                     itemName != 'emulated' &&
                                                     itemName != 'self';
                                  
                                  return ListTile(
                                    leading: Icon(
                                      isDirectory
                                          ? (isParent 
                                              ? Icons.arrow_upward 
                                              : (isUsbDrive ? Icons.usb : Icons.folder))
                                          : _getFileIcon(item.path),
                                      color: isDirectory 
                                          ? (isUsbDrive ? Colors.orange : Colors.blue) 
                                          : Colors.grey,
                                    ),
                                    title: Text(
                                      isParent 
                                          ? '.. (Parent)' 
                                          : (isUsbDrive && isDirectory 
                                              ? '$itemName (USB Drive)' 
                                              : itemName),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: isUsbDrive ? FontWeight.w600 : FontWeight.normal,
                                      ),
                                    ),
                                    subtitle: isUsbDrive && isDirectory
                                        ? const Text(
                                            'External Storage',
                                            style: TextStyle(fontSize: 12, color: Colors.orange),
                                          )
                                        : null,
                                    trailing: isDirectory
                                        ? const Icon(Icons.chevron_right)
                                        : Text(
                                            _formatFileSize(item),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                    onTap: () => _onItemSelected(item),
                                  );
                                },
                              ),
          ),

          // Bottom action button (for directory selection)
          if (widget.selectDirectory && _currentPath != null && _error == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: ElevatedButton.icon(
                onPressed: _selectCurrentDirectory,
                icon: const Icon(Icons.check),
                label: const Text('Select This Folder'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    switch (ext) {
      case '.zip':
        return Icons.archive;
      case '.html':
      case '.htm':
        return Icons.html;
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatFileSize(FileSystemEntity entity) {
    if (entity is! File) return '';
    
    try {
      final size = entity.lengthSync();
      if (size < 1024) return '$size B';
      if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
      if (size < 1024 * 1024 * 1024) {
        return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } catch (e) {
      return '';
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../models/book.dart';
import '../routes.dart';
import '../utils/zip_handler.dart';
import '../utils/connectivity_helper.dart';
import '../services/background_sync_service.dart';

/// Per-book sync state: thumbnail, progress %, status.
class SyncItem {
  final int courseId;
  final String title;
  final String? thumbnail;
  final String productName;
  final Map<String, dynamic> course;
  String status; // pending | downloading | done | error
  int progress;  // 0-100

  SyncItem({
    required this.courseId,
    required this.title,
    required this.productName,
    required this.course,
    this.thumbnail,
    this.status = 'pending',
    this.progress = 0,
  });
}

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  bool _isLoading = false;
  String _statusMessage = 'Preparing to sync...';
  int _totalBooks = 0;
  int _downloadedBooks = 0;
  bool _syncComplete = false;
  List<SyncItem> _syncItems = [];

  bool _fetchDone = false;
  String? _storageLocationForSync;
  List<Map<String, dynamic>> _allCoursesForSync = [];

  @override
  void initState() {
    super.initState();
    _startSync();
  }

  Future<void> _startSync() async {
    final prefs = await SharedPreferences.getInstance();
    final syncType = prefs.getString('syncType') ?? 'online';
    final storageLocation = prefs.getString('storageLocation');

    setState(() {
      _isLoading = true;
      _statusMessage = 'Starting sync process...';
    });

    if (syncType == 'online') {
      await _fetchAndPrepare();
    } else {
      await _syncOffline(storageLocation);
    }
  }

  Future<void> _runDownloadsNow() async {
    if (_storageLocationForSync == null) return;
    setState(() {
      _isLoading = true;
      _statusMessage = 'Downloading ${_syncItems.length} book(s)...';
    });
    await DatabaseService.logAllBooks();
    final futures = <Future<void>>[];
    for (int i = 0; i < _syncItems.length; i++) {
      futures.add(_downloadOneCourse(i, _storageLocationForSync!));
    }
    await Future.wait(futures);
    await DatabaseService.logAllBooks();
    final done = _syncItems.where((s) => s.status == 'done').length;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('syncCompleted', true);
    setState(() {
      _isLoading = false;
      _downloadedBooks = done;
      _statusMessage = 'Sync complete! Downloaded $done/${_syncItems.length} books.';
      _syncComplete = true;
    });
  }

  Future<void> _syncOnline() async {
    try {
      // Get storage location from preferences
      final prefs = await SharedPreferences.getInstance();
      final storageLocation = prefs.getString('storageLocation');
      
      if (storageLocation == null || storageLocation.isEmpty || storageLocation == 'Not selected') {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Storage location not configured. Please select a storage location in Settings.';
        });
        return;
      }

      // Check internet connectivity before starting online sync
      setState(() {
        _statusMessage = 'Checking internet connection...';
      });
      
      final hasInternet = await ConnectivityHelper.hasInternetConnection();
      if (!hasInternet) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Internet connection required for online sync. Please check your network connection and try again.';
        });
        return;
      }

      setState(() {
        _statusMessage = 'Fetching books from server...';
      });

      // Fetch product list from API
      final result = await ApiService.getProductList();

      if (result['success'] != true) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Failed to fetch books: ${result['message']}';
        });
        return;
      }

      // Extract all courses from nested product structure
      final responseData = result['responseData'] as Map<String, dynamic>?;
      List<Map<String, dynamic>> allCourses = [];
      
      if (responseData != null && responseData['data'] != null) {
        final data = responseData['data'] as Map<String, dynamic>;
        final products = data['products'] as List<dynamic>?;
        
        if (products != null) {
          // Extract all courses from all products
          for (final product in products) {
            final productMap = product as Map<String, dynamic>;
            final courses = productMap['courses'] as List<dynamic>?;
            
            if (courses != null) {
              for (final course in courses) {
                final courseMap = course as Map<String, dynamic>;
                // Include product info with each course
                allCourses.add({
                  ...courseMap,
                  'product_id': productMap['id'],
                  'product_name': productMap['name'],
                  'product_description': productMap['description'],
                  'product_thumbnail': productMap['thumbnail'],
                });
              }
            }
          }
        }
      }
      
      _totalBooks = allCourses.length;

      if (_totalBooks == 0) {
        // Mark sync as completed even with 0 books
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('syncCompleted', true);
        
        setState(() {
          _isLoading = false;
          _statusMessage = 'No books found on server.';
          _syncComplete = true;
        });
        return;
      }

      // Save all courses to database first
      setState(() {
        _statusMessage = 'Saving $_totalBooks book(s) to database...';
      });

      for (final course in allCourses) {
        final courseId = course['id'] as int? ?? 0;
        final title = course['title']?.toString() ?? 'Untitled';
        final description = course['description']?.toString() ?? '';
        final thumbnail = course['thumbnail']?.toString();
        final productName = course['product_name']?.toString() ?? 'Unknown Product';

        // Save to database without file path (will be updated after download)
        final book = Book(
          title: title,
          author: productName, // Using product name as author
          progress: 0,
          thumbnail: thumbnail,
          contentUrl: '', // Will be set after download
        );

        await DatabaseService.insertBook(
          book,
          courseId: courseId,
          filePath: null, // Will be set after download
        );
      }

      debugPrint('✅ Saved $_totalBooks courses to database');

      // Build sync items for UI (thumbnail, progress %, status)
      final items = <SyncItem>[];
      for (final course in allCourses) {
        final courseId = course['id'] as int? ?? 0;
        final title = course['title']?.toString() ?? 'Untitled';
        final productName = course['product_name']?.toString() ?? 'Unknown Product';
        final thumb = course['thumbnail']?.toString() ?? course['product_thumbnail']?.toString();
        items.add(SyncItem(
          courseId: courseId,
          title: title,
          productName: productName,
          course: course as Map<String, dynamic>,
          thumbnail: thumb,
          status: 'pending',
          progress: 0,
        ));
      }

      _storageLocationForSync = storageLocation;
      _allCoursesForSync = List<Map<String, dynamic>>.from(allCourses);
      setState(() {
        _statusMessage = 'Downloading $_totalBooks book(s)...';
        _downloadedBooks = 0;
        _syncItems = items;
        _fetchDone = true;
        _isLoading = true;
      });

      // Auto-start downloads: list API → save to DB → download via download API
      debugPrint('📥 Starting downloads for ${items.length} book(s)...');
      await _runDownloadsNow();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error during sync: $e';
      });
    }
  }

  Future<void> _fetchAndPrepare() async {
    await _syncOnline();
  }

  Future<void> _downloadOneCourse(int index, String storageLocation) async {
    if (index < 0 || index >= _syncItems.length) return;
    final item = _syncItems[index];
    final courseId = item.courseId;
    final title = item.title;
    final productName = item.productName;
    final course = item.course;

    void update({String? status, int? progress}) {
      if (!mounted) return;
      setState(() {
        if (status != null) item.status = status;
        if (progress != null) item.progress = progress;
      });
    }

    try {
      update(status: 'downloading', progress: 0);
      debugPrint('📥 Downloading course: courseId=$courseId, title="$title"');

      final downloadResult = await ApiService.downloadCourse(
        courseId,
        targetDirectory: storageLocation,
        onProgress: (p) => update(progress: p),
      );

      if (downloadResult['success'] != true) {
        update(status: 'error');
        return;
      }

      final filePath = downloadResult['filePath'] as String;
      // Save ZIP path only; extraction happens when user opens the book
      final finalPath = filePath;
      final encBookId = downloadResult['encBookId'] as String?;
      final encKeyB64 = downloadResult['encKeyB64'] as String?;
      final encNonceB64 = downloadResult['encNonceB64'] as String?;
      debugPrint('🔐 [SYNC] enc keys from API: bookId=$encBookId '
          'keyEncB64=${encKeyB64 != null ? '***' : 'null'} '
          'keyNonceB64=${encNonceB64 != null ? '***' : 'null'}');

      final thumb = course['thumbnail']?.toString() ?? course['product_thumbnail']?.toString();
      final book = Book(
        title: title,
        author: productName,
        progress: 0,
        thumbnail: thumb,
        contentUrl: finalPath != null && finalPath.startsWith('/')
            ? 'file://$finalPath'
            : finalPath != null && finalPath.startsWith('file://')
                ? finalPath
                : 'file:///$finalPath',
        encBookId: encBookId,
        encKeyB64: encKeyB64,
        encNonceB64: encNonceB64,
      );

      await DatabaseService.insertBook(book, courseId: courseId, filePath: finalPath);
      update(status: 'done', progress: 100);
      if (mounted) {
        setState(() {
          _downloadedBooks = _syncItems.where((s) => s.status == 'done').length;
        });
      }
      debugPrint('✅ Downloaded: $title');
    } catch (e) {
      debugPrint('Error downloading book $title: $e');
      update(status: 'error');
    }
  }

  Future<void> _syncOffline(String? storageLocation) async {
    if (storageLocation == null || storageLocation.isEmpty || storageLocation == 'Not selected') {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Please select a storage location first.';
      });
      
      // Navigate back to settings after a delay
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.pop(context);
      }
      return;
    }

    try {
      // Even for offline sync, we need internet to get the book list from API
      setState(() {
        _statusMessage = 'Checking internet connection...';
      });
      
      final hasInternet = await ConnectivityHelper.hasInternetConnection();
      if (!hasInternet) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Internet connection required to fetch book list. Books will be scanned from your storage location once the list is retrieved.';
        });
        return;
      }

      setState(() {
        _statusMessage = 'Fetching book list from server...';
      });

      // Step 1: Get list of books from API
      final result = await ApiService.getProductList();

      if (result['success'] != true) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Failed to fetch book list: ${result['message']}';
        });
        return;
      }

      final products = result['products'] as List<Map<String, dynamic>>;
      _totalBooks = products.length;

      if (_totalBooks == 0) {
        // Mark sync as completed even with 0 books
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('syncCompleted', true);
        
        setState(() {
          _isLoading = false;
          _statusMessage = 'No books found on server.';
          _syncComplete = true;
        });
        return;
      }

      setState(() {
        _statusMessage = 'Checking $_totalBooks book(s) in folder...';
        _downloadedBooks = 0;
      });

      // Step 2: Check each book in the selected folder
      int foundCount = 0;
      
      for (int i = 0; i < products.length; i++) {
        final product = products[i];
        final courseId = product['id'] ?? product['course_id'] ?? i + 1;
        final title = product['title']?.toString() ?? product['name']?.toString() ?? 'Untitled';
        final author = product['author']?.toString() ?? product['author_name']?.toString() ?? 'Unknown Author';

        setState(() {
          _statusMessage = 'Checking: $title (${i + 1}/$_totalBooks)';
        });

        // Check if book exists in the folder
        bool bookFound = false;
        String? bookPath;

        try {
          // Look for ZIP files with course ID in name
          final coursesDir = Directory(path.join(storageLocation, 'courses'));
          if (await coursesDir.exists()) {
            await for (final entity in coursesDir.list()) {
              if (entity is File) {
                final fileName = path.basenameWithoutExtension(entity.path).toLowerCase();
                if (fileName.contains('course_$courseId') || 
                    fileName.contains('$courseId')) {
                  bookPath = entity.path;
                  bookFound = true;
                  break;
                }
              }
            }
          }

          // Also check in books folder
          if (!bookFound) {
            final booksDir = Directory(path.join(storageLocation, 'books'));
            if (await booksDir.exists()) {
              await for (final entity in booksDir.list()) {
                if (entity is Directory || entity is File) {
                  final name = path.basename(entity.path).toLowerCase();
                  // Check if folder/file name contains course ID or title keywords
                  if (name.contains('course_$courseId') || 
                      name.contains('$courseId') ||
                      name.contains(title.toLowerCase().substring(0, title.length > 10 ? 10 : title.length))) {
                    // Check for index.html inside
                    if (entity is Directory) {
                      final indexHtml = await ZipHandler.findIndexHtml(entity.path);
                      if (indexHtml != null) {
                        bookPath = indexHtml;
                        bookFound = true;
                        break;
                      }
                    } else if (entity.path.toLowerCase().endsWith('.html') ||
                               entity.path.toLowerCase().endsWith('.zip')) {
                      bookPath = entity.path;
                      bookFound = true;
                      break;
                    }
                  }
                }
              }
            }
          }

          // If book found, save to database
          if (bookFound && bookPath != null) {
            // Store path as-is (ZIP or folder); extraction happens when user opens book
            final finalPath = bookPath;

            // Create book object
            final book = Book(
              title: title,
              author: author,
              progress: 0,
              thumbnail: product['thumbnail']?.toString() ?? product['thumbnail_url']?.toString(),
              contentUrl: finalPath != null && finalPath.startsWith('/')
                  ? 'file://$finalPath'
                  : finalPath != null && finalPath.startsWith('file://')
                      ? finalPath
                      : 'file:///$finalPath',
            );

            // Save to database
            await DatabaseService.insertBook(
              book,
              courseId: courseId is int ? courseId : int.tryParse(courseId.toString()),
              filePath: finalPath,
            );

            foundCount++;
          }

          _downloadedBooks++;
        } catch (e) {
          debugPrint('Error checking book $title: $e');
          _downloadedBooks++;
          // Continue with next book
        }
      }

      setState(() {
        _isLoading = false;
        _statusMessage = 'Sync complete! Found $foundCount/$_totalBooks books in folder.';
        _syncComplete = true;
      });

      // Mark sync as completed in preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('syncCompleted', true);

      // Show completion and wait for user to click "Go to Bookshelf"
      // Don't auto-navigate, wait for user action
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error during sync: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Syncing Books'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (_isLoading && (_totalBooks > 0 || _syncItems.isNotEmpty)) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: () {
                  final total = _totalBooks > 0 ? _totalBooks : _syncItems.length;
                  if (total <= 0) return null;
                  return (_downloadedBooks / total).clamp(0.0, 1.0);
                }(),
              ),
              Text(
                '$_downloadedBooks / ${_totalBooks > 0 ? _totalBooks : _syncItems.length} complete',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
            if (_fetchDone &&
                _syncItems.isNotEmpty &&
                !_syncComplete &&
                !_isLoading) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _runDownloadsNow,
                      icon: const Icon(Icons.download),
                      label: const Text('Download all'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  if (Platform.isAndroid) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await enqueueBackgroundSync(_allCoursesForSync);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Syncing in background. You can close the app.',
                              ),
                              duration: Duration(seconds: 4),
                            ),
                          );
                          Navigator.pushReplacementNamed(
                              context, AppRoutes.home);
                        },
                        icon: const Icon(Icons.cloud_download),
                        label: const Text('Sync in background'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: _syncItems.isEmpty && !_syncComplete
                  ? Center(
                      child: _isLoading
                          ? const CircularProgressIndicator()
                          : const SizedBox.shrink(),
                    )
                  : _syncItems.isEmpty && _syncComplete
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 64,
                                color: Colors.green,
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pushReplacementNamed(
                                      context, AppRoutes.home);
                                },
                                icon: const Icon(Icons.library_books),
                                label: const Text('Go to Bookshelf'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32,
                                    vertical: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _syncItems.length,
                          itemBuilder: (context, i) {
                            final item = _syncItems[i];
                            return _SyncItemTile(item: item);
                          },
                        ),
            ),
            if (_syncComplete && _syncItems.isNotEmpty) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, AppRoutes.home);
                },
                icon: const Icon(Icons.library_books),
                label: const Text('Go to Bookshelf'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SyncItemTile extends StatelessWidget {
  final SyncItem item;

  const _SyncItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDone = item.status == 'done';
    final isError = item.status == 'error';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: item.thumbnail != null && item.thumbnail!.isNotEmpty
                  ? Image.network(
                      item.thumbnail!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: isDone || isError
                        ? (isDone ? 1.0 : 0.0)
                        : (item.progress / 100).clamp(0.0, 1.0),
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isError ? Colors.red : Colors.green,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isDone
                        ? 'Done'
                        : isError
                            ? 'Error'
                            : '${item.progress}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: isError ? Colors.red : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (isDone)
              const Icon(Icons.check_circle, color: Colors.green, size: 24),
            if (isError)
              const Icon(Icons.error, color: Colors.red, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 56,
      height: 56,
      color: Colors.grey.shade300,
      child: Icon(Icons.book, color: Colors.grey.shade600),
    );
  }
}

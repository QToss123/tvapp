import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../models/book.dart';
import '../routes.dart';
import '../utils/zip_handler.dart';
import '../utils/connectivity_helper.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  bool _isLoading = false;
  String _statusMessage = 'Preparing to sync...';
  int _progress = 0;
  int _totalBooks = 0;
  int _downloadedBooks = 0;
  bool _syncComplete = false;

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
      await _syncOnline();
    } else {
      await _syncOffline(storageLocation);
    }
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

      setState(() {
        _statusMessage = 'Downloading $_totalBooks book(s)...';
        _downloadedBooks = 0;
        _progress = 0;
      });

      // Download each course one by one
      for (int i = 0; i < allCourses.length; i++) {
        final course = allCourses[i];
        // IMPORTANT: Use same courseId logic as initial save to ensure database update works
        final courseId = course['id'] as int? ?? 0;
        final title = course['title']?.toString() ?? 'Untitled';
        final productName = course['product_name']?.toString() ?? 'Unknown Product';
        
        debugPrint('📥 Downloading course: courseId=$courseId, title="$title"');

        setState(() {
          _statusMessage = 'Downloading: $title ($_downloadedBooks/$_totalBooks)';
        });

        try {
          // Download the course using the download API which returns download_url
          final downloadResult = await ApiService.downloadCourse(
            courseId,
            targetDirectory: storageLocation, // Download to external storage
            onProgress: (progress) {
              setState(() {
                _progress = progress;
              });
            },
          );

          if (downloadResult['success'] == true) {
            final filePath = downloadResult['filePath'] as String;
            String? finalPath = filePath;

            // If it's a ZIP file, extract it to the same external storage location
            if (filePath.toLowerCase().endsWith('.zip')) {
              setState(() {
                _statusMessage = 'Extracting: $title';
              });

              // Extract ZIP file - ZipHandler will extract to temp directory
              // We need to move extracted files to external storage
              final extracted = await ZipHandler.processBookFile(filePath);
              
              if (extracted.wasExtracted) {
                // Determine if extracted.path is a file or directory
                final extractedFile = File(extracted.path);
                final extractedDir = Directory(extracted.path);
                
                String extractedDirectoryPath;
                String? indexHtmlPath;
                
                // Check if extracted.path points to a file (index.html) or directory
                if (await extractedFile.exists()) {
                  // It's a file (index.html), use its parent directory
                  extractedDirectoryPath = extractedFile.parent.path;
                  indexHtmlPath = extracted.path;
                  debugPrint('Extracted path is a file, using parent directory: $extractedDirectoryPath');
                } else if (await extractedDir.exists()) {
                  // It's a directory
                  extractedDirectoryPath = extracted.path;
                  debugPrint('Extracted path is a directory: $extractedDirectoryPath');
                } else {
                  throw Exception('Extracted path does not exist: ${extracted.path}');
                }
                
                final booksDir = path.join(storageLocation, 'books');
                final bookFolderName = 'course_${courseId}_${DateTime.now().millisecondsSinceEpoch}';
                final targetBookDir = path.join(booksDir, bookFolderName);
                
                // Create books directory if it doesn't exist
                final booksDirectory = Directory(booksDir);
                if (!await booksDirectory.exists()) {
                  await booksDirectory.create(recursive: true);
                }
                
                // Copy extracted files to external storage
                final sourceDir = Directory(extractedDirectoryPath);
                if (sourceDir.path != targetBookDir) {
                  final targetDir = Directory(targetBookDir);
                  if (await targetDir.exists()) {
                    await targetDir.delete(recursive: true);
                  }
                  await targetDir.create(recursive: true);
                  
                  // Copy all files from extracted directory
                  await for (final entity in sourceDir.list(recursive: true)) {
                    final relativePath = path.relative(entity.path, from: extractedDirectoryPath);
                    final targetPath = path.join(targetBookDir, relativePath);
                    
                    if (entity is File) {
                      final targetFile = File(targetPath);
                      await targetFile.parent.create(recursive: true);
                      await entity.copy(targetPath);
                    }
                  }
                  
                  // Find index.html in the new location
                  final indexHtml = await ZipHandler.findIndexHtml(targetBookDir);
                  if (indexHtml != null) {
                    finalPath = indexHtml;
                  } else {
                    finalPath = targetBookDir;
                  }
                } else {
                  // Already in target location, use the index.html path if we have it
                  finalPath = indexHtmlPath ?? targetBookDir;
                }
              } else {
                finalPath = filePath;
              }
            }

            // Create book object with final file path
            final book = Book(
              title: title,
              author: productName, // Use productName from course data
              progress: 0,
              thumbnail: course['thumbnail']?.toString() ?? course['product_thumbnail']?.toString(),
              contentUrl: finalPath != null && finalPath.startsWith('/')
                  ? 'file://$finalPath'
                  : finalPath != null && finalPath.startsWith('file://')
                      ? finalPath
                      : 'file:///$finalPath',
            );

            // Update database with file path after successful download
            debugPrint('💾 Saving book to database: courseId=$courseId, title="$title", finalPath=$finalPath');
            final dbResult = await DatabaseService.insertBook(
              book,
              courseId: courseId,
              filePath: finalPath,
            );
            debugPrint('✅ Database save result: $dbResult');

            _downloadedBooks++;
            setState(() {
              _progress = 0;
            });
          }
        } catch (e) {
          debugPrint('Error downloading book $title: $e');
          // Continue with next book
        }
      }

      setState(() {
        _isLoading = false;
        _statusMessage = 'Sync complete! Downloaded $_downloadedBooks/$_totalBooks books.';
        _syncComplete = true;
      });

      // Mark sync as completed in preferences
      await prefs.setBool('syncCompleted', true);

      // Don't auto-navigate - wait for user to click "Go to Bookshelf"
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error during sync: $e';
      });
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
            String? finalPath = bookPath;
            
            // If it's a ZIP, extract it
            if (bookPath.toLowerCase().endsWith('.zip')) {
              final extracted = await ZipHandler.processBookFile(bookPath);
              if (extracted.wasExtracted) {
                final indexHtml = await ZipHandler.findIndexHtml(extracted.path);
                if (indexHtml != null) {
                  finalPath = indexHtml;
                } else {
                  finalPath = extracted.path;
                }
              }
            }

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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isLoading) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
              ] else if (_syncComplete) ...[
                Icon(
                  Icons.check_circle,
                  size: 64,
                  color: Colors.green,
                ),
                const SizedBox(height: 24),
              ],
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_isLoading && _totalBooks > 0) ...[
                const SizedBox(height: 32),
                LinearProgressIndicator(
                  value: _downloadedBooks > 0 
                      ? (_downloadedBooks / _totalBooks).clamp(0.0, 1.0)
                      : null,
                ),
                const SizedBox(height: 16),
                Text(
                  'Progress: $_downloadedBooks / $_totalBooks',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
              if (_syncComplete && !_isLoading) ...[
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () {
                    debugPrint('🔄 [SYNC] User clicked "Go to Bookshelf" button');
                    debugPrint('🔄 [SYNC] Navigating to home screen using pushReplacementNamed...');
                    Navigator.pushReplacementNamed(context, AppRoutes.home);
                    debugPrint('🔄 [SYNC] Navigation completed - HomeScreen should initialize now');
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
      ),
    );
  }
}

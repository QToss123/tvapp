import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../utils/thumbnail_helper.dart';
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
  String status; // pending | downloading | done | error | paused
  int progress;  // 0-100
  bool selected; // for select/unselect
  bool isPaused; // when true, download will abort (for pause support)

  SyncItem({
    required this.courseId,
    required this.title,
    required this.productName,
    required this.course,
    this.thumbnail,
    this.status = 'pending',
    this.progress = 0,
    this.selected = true,
    this.isPaused = false,
  });
}

class SyncScreen extends StatefulWidget {
  const SyncScreen({
    super.key,
    this.showAsPanel = false,
    this.onClose,
  });

  final bool showAsPanel;
  final VoidCallback? onClose;

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

  /// TV / large screen: slight scale for readability without bulky cards.
  static bool _isTvOrLargeScreen(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 600;
  }

  static double _tvFontSize(BuildContext context, double base) {
    return _isTvOrLargeScreen(context) ? base * 1.1 : base;
  }

  static double _tvSize(BuildContext context, double base) {
    return _isTvOrLargeScreen(context) ? base * 1.15 : base;
  }

  static int _tvGridColumns(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1200) return 8;
    if (width >= 900) return 6;
    if (width >= 600) return 5;
    return 4;
  }

  static double _tvGridAspectRatio(BuildContext context) {
    return _isTvOrLargeScreen(context) ? 0.62 : 0.65;
  }

  @override
  void initState() {
    super.initState();
    _startSync();
  }

  Future<void> _startSync() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Starting sync process...';
    });
    await _fetchAndPrepare();
  }

  /// Updates _statusMessage and _downloadedBooks from current _syncItems state.
  void _updateStatusFromItems() {
    final done = _syncItems.where((s) => s.status == 'done').length;
    final downloading = _syncItems.where((s) => s.status == 'downloading').length;
    final paused = _syncItems.where((s) => s.status == 'paused').length;
    final error = _syncItems.where((s) => s.status == 'error').length;
    _downloadedBooks = done;
    final total = _syncItems.length;
    if (downloading > 0 || paused > 0 || (done > 0 && done < total && !_syncComplete)) {
      final parts = <String>['$done done'];
      if (downloading > 0) parts.add('$downloading downloading');
      if (paused > 0) parts.add('$paused paused');
      if (error > 0) parts.add('$error failed');
      _statusMessage = '${parts.join(', ')} ($total total)';
    }
  }

  Future<void> _runDownloadsNow() async {
    if (_storageLocationForSync == null) return;
    final selectedItems = _syncItems.where((s) => s.selected).toList();
    if (selectedItems.isEmpty) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Please select at least one course to download.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _statusMessage = 'Downloading ${selectedItems.length} book(s)...';
    });
    await DatabaseService.logAllBooks();
    final futures = <Future<void>>[];
    for (int i = 0; i < _syncItems.length; i++) {
      if (_syncItems[i].selected) {
        futures.add(_downloadOneCourse(i, _storageLocationForSync!));
      }
    }
    await Future.wait(futures);
    await DatabaseService.logAllBooks();
    final done = _syncItems.where((s) => s.status == 'done').length;
    final paused = _syncItems.where((s) => s.status == 'paused').length;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('syncCompleted', true);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _downloadedBooks = done;
      _statusMessage = paused > 0
          ? 'Sync complete! Downloaded $done/${_syncItems.length} books. $paused paused.'
          : 'Sync complete! Downloaded $done/${_syncItems.length} books.';
      _syncComplete = true;
    });
  }

  Future<void> _syncOnline() async {
    try {
      // Get storage location from preferences
      final prefs = await SharedPreferences.getInstance();
      final storageLocation = prefs.getString('storageLocation');
      
      if (storageLocation == null || storageLocation.isEmpty || storageLocation == 'Not selected') {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _statusMessage = 'Storage location not configured. Please select a storage location in Settings.';
        });
        return;
      }

      // Check internet connectivity before starting online sync
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Checking internet connection...';
      });
      
      final hasInternet = await ConnectivityHelper.hasInternetConnection();
      if (!hasInternet) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _statusMessage = 'Internet connection required for online sync. Please check your network connection and try again.';
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _statusMessage = 'Fetching books from server...';
      });

      // Fetch product list from API
      final result = await ApiService.getProductList();

      if (result['success'] != true) {
        if (!mounted) return;
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
        
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _statusMessage = 'No books found on server.';
          _syncComplete = true;
        });
        return;
      }

      // Save all courses to database first
      if (!mounted) return;
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
          selected: true,
        ));
      }

      _storageLocationForSync = storageLocation;
      _allCoursesForSync = List<Map<String, dynamic>>.from(allCourses);
      if (!mounted) return;
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
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Error during sync: $e';
        });
      }
    }
  }

  Future<void> _fetchAndPrepare() async {
    await _syncOnline();
  }

  Future<void> _downloadOneCourse(int index, String storageLocation) async {
    if (index < 0 || index >= _syncItems.length) return;
    final item = _syncItems[index];
    if (!item.selected) return;
    // Skip if already downloaded (file exists and in DB)
    final filePath = await DatabaseService.getFilePathByCourseId(item.courseId);
    if (filePath != null && filePath.isNotEmpty) {
      final file = File(filePath);
      if (await file.exists()) {
        debugPrint('⏭️ Skipping already downloaded: ${item.title}');
        if (mounted) {
          setState(() {
            item.status = 'done';
            item.progress = 100;
            _updateStatusFromItems();
          });
        }
        return;
      }
    }
    final courseId = item.courseId;
    final title = item.title;
    final productName = item.productName;
    final course = item.course;

    void update({String? status, int? progress}) {
      if (!mounted) return;
      setState(() {
        if (status != null) item.status = status;
        if (progress != null) item.progress = progress;
        _updateStatusFromItems();
      });
    }

    try {
      item.isPaused = false;
      update(status: 'downloading', progress: 0);
      debugPrint('📥 Downloading course: courseId=$courseId, title="$title"');

      final downloadResult = await ApiService.downloadCourse(
        courseId,
        targetDirectory: storageLocation,
        onProgress: (p) => update(progress: p),
        isCancelled: () => item.isPaused,
        checkExisting: (encId) => DatabaseService.getFilePathByEncBookId(encId),
      );

      if (downloadResult['success'] != true) {
        if (downloadResult['cancelled'] == true) {
          update(status: 'paused');
        } else {
          update(status: 'error');
        }
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

      final encBookPath = downloadResult['encBookPath'] as String?;
      final thumb = course['thumbnail']?.toString() ?? course['product_thumbnail']?.toString();
      String? thumbnailLocalPath;
      if (thumb != null && thumb.isNotEmpty && thumb.startsWith('http')) {
        final thumbnailsDir = path.join(storageLocation, 'thumbnails');
        final id = encBookId ?? 'course_$courseId';
        thumbnailLocalPath = await ThumbnailHelper.downloadAndSave(
          thumb,
          thumbnailsDir: thumbnailsDir,
          id: id,
        );
      }
      final book = Book(
        title: title,
        author: productName,
        progress: 0,
        thumbnail: thumb,
        thumbnailLocalPath: thumbnailLocalPath,
        contentUrl: finalPath != null && finalPath.startsWith('/')
            ? 'file://$finalPath'
            : finalPath != null && finalPath.startsWith('file://')
                ? finalPath
                : 'file:///$finalPath',
        encBookId: encBookId,
        encBookPath: encBookPath,
        encKeyB64: encKeyB64,
        encNonceB64: encNonceB64,
      );

      await DatabaseService.insertBook(book, courseId: courseId, filePath: finalPath);
      update(status: 'done', progress: 100);
      debugPrint('✅ Downloaded: $title');
    } catch (e) {
      debugPrint('Error downloading book $title: $e');
      update(status: 'error');
    }
  }

  void _handleBack() {
    final downloading = _isLoading &&
        _syncItems.any((s) => s.status == 'downloading' || s.status == 'pending');
    if (downloading && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Downloads will continue in background.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
    if (widget.showAsPanel) {
      widget.onClose?.call();
      if (mounted) Navigator.pop(context);
    } else {
      Navigator.maybePop(context);
    }
  }

  Widget _buildBody(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: _tvFontSize(context, 18),
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade900,
              ),
            ),
            if (_isLoading && (_totalBooks > 0 || _syncItems.isNotEmpty)) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: () {
                  final total = _totalBooks > 0 ? _totalBooks : _syncItems.length;
                  if (total <= 0) return null;
                  return (_downloadedBooks / total).clamp(0.0, 1.0);
                }(),
                minHeight: _tvSize(context, 8),
                backgroundColor: Colors.grey.shade300,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              const SizedBox(height: 6),
              Text(
                '$_downloadedBooks / ${_totalBooks > 0 ? _totalBooks : _syncItems.length} complete',
                style: TextStyle(
                  fontSize: _tvFontSize(context, 14),
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
            if (_fetchDone &&
                _syncItems.isNotEmpty &&
                !_syncComplete &&
                !_isLoading) ...[
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final selectedCount = _syncItems.where((s) => s.selected).length;
                  return Text(
                    '${selectedCount} of ${_syncItems.length} selected (check/uncheck to choose which to download)',
                    style: TextStyle(
                      fontSize: _tvFontSize(context, 15),
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final selectedCount = _syncItems.where((s) => s.selected).length;
                        return ElevatedButton.icon(
                          onPressed: selectedCount > 0 ? _runDownloadsNow : null,
                          icon: const Icon(Icons.download, size: 20),
                          label: Text(
                            selectedCount > 0
                                ? 'Download ($selectedCount selected)'
                                : 'Select at least 1 book',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          ),
                        );
                      },
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
                          _closeOrGoToBookshelf();
                        },
                        icon: const Icon(Icons.cloud_download, size: 20),
                        label: const Text('Sync in background', style: TextStyle(fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                              const Icon(Icons.check_circle, size: 56, color: Colors.green),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: _closeOrGoToBookshelf,
                                icon: const Icon(Icons.library_books),
                                label: const Text('Go to Bookshelf', style: TextStyle(fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                ),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _tvGridColumns(context),
                            childAspectRatio: _tvGridAspectRatio(context),
                            crossAxisSpacing: _tvSize(context, 12),
                            mainAxisSpacing: _tvSize(context, 12),
                          ),
                          padding: EdgeInsets.only(bottom: _tvSize(context, 24)),
                          itemCount: _syncItems.length,
                          itemBuilder: (context, i) {
                            final item = _syncItems[i];
                            return _SyncItemGridTile(
                              item: item,
                              onSelectChanged: (selected) {
                                if (!mounted) return;
                                setState(() {
                                  item.selected = selected;
                                });
                              },
                              onPause: item.status == 'downloading'
                                  ? () {
                                      if (!mounted) return;
                                      setState(() {
                                        item.isPaused = true;
                                      });
                                    }
                                  : null,
                              onResume: (item.status == 'error' || item.status == 'paused') &&
                                      _storageLocationForSync != null
                                  ? () => _downloadOneCourse(i, _storageLocationForSync!)
                                  : null,
                            );
                          },
                        ),
            ),
            if (_syncComplete && _syncItems.isNotEmpty) ...[
              const SizedBox(height: 16),
              Focus(
                autofocus: true,
                child: ElevatedButton.icon(
                  onPressed: _closeOrGoToBookshelf,
                  icon: const Icon(Icons.library_books),
                  label: const Text('Go to Bookshelf', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    elevation: 6,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
  }

  void _closeOrGoToBookshelf() {
    if (widget.showAsPanel) {
      widget.onClose?.call();
      if (mounted) Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    if (widget.showAsPanel) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).colorScheme.surface,
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: _handleBack,
                  ),
                  const Expanded(
                    child: Text(
                      'Download books',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
          Expanded(child: body),
        ],
      );
    }
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop &&
            _isLoading &&
            _syncItems.any((s) => s.status == 'downloading' || s.status == 'pending')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Downloads will continue in background.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Syncing Books', style: TextStyle(fontWeight: FontWeight.w600)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: _handleBack,
          ),
        ),
        body: body,
      ),
    );
  }
}

class _SyncItemGridTile extends StatelessWidget {
  final SyncItem item;
  final ValueChanged<bool>? onSelectChanged;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  const _SyncItemGridTile({
    required this.item,
    this.onSelectChanged,
    this.onPause,
    this.onResume,
  });

  bool _isTv(BuildContext context) => MediaQuery.sizeOf(context).width >= 600;

  double _fs(BuildContext context, double base) =>
      _isTv(context) ? base * 1.1 : base;

  double _px(BuildContext context, double base) =>
      _isTv(context) ? base * 1.1 : base;

  @override
  Widget build(BuildContext context) {
    final isDone = item.status == 'done';
    final isError = item.status == 'error';
    final isPaused = item.status == 'paused';
    final isDownloading = item.status == 'downloading';
    final tv = _isTv(context);
    final statusColor = isError
        ? Colors.red
        : isPaused
            ? Colors.orange
            : isDone
                ? Colors.green
                : Colors.blue;

    return Focus(
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: hasFocus
                  ? Border.all(color: Colors.blueAccent, width: 2)
                  : null,
              boxShadow: hasFocus
                  ? [BoxShadow(color: Colors.blueAccent.withOpacity(0.3), blurRadius: 6, spreadRadius: 0)]
                  : null,
            ),
            child: Card(
              clipBehavior: Clip.antiAlias,
              elevation: hasFocus ? 8 : 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              color: Colors.grey.shade50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Thumbnail
                  Expanded(
                    flex: 3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRect(
                          child: item.thumbnail != null && item.thumbnail!.isNotEmpty
                              ? Image.network(
                                  item.thumbnail!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _placeholder(context),
                                )
                              : _placeholder(context),
                        ),
                        // Subtle gradient for title readability
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: _px(context, 20),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.6),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (onSelectChanged != null && !isDone && !isError)
                          Positioned(
                            top: _px(context, 4),
                            left: _px(context, 4),
                            child: Material(
                              color: Colors.white.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(6),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => onSelectChanged!(!item.selected),
                                child: Padding(
                                  padding: EdgeInsets.all(_px(context, 4)),
                                  child: Checkbox(
                                    value: item.selected,
                                    onChanged: (v) => onSelectChanged!(v ?? true),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: tv
                                        ? VisualDensity.standard
                                        : VisualDensity.compact,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (isDone)
                          Positioned(
                            top: _px(context, 4),
                            right: _px(context, 4),
                            child: Icon(Icons.check_circle, color: Colors.green, size: _fs(context, 16)),
                          ),
                        if (isError)
                          Positioned(
                            top: _px(context, 4),
                            right: _px(context, 4),
                            child: Icon(Icons.error, color: Colors.red, size: _fs(context, 16)),
                          ),
                      ],
                    ),
                  ),
                  // Title and progress (flexible to avoid overflow)
                  Expanded(
                    flex: 2,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        horizontal: _px(context, 4),
                        vertical: _px(context, 3),
                      ),
                      color: Colors.white,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: _fs(context, 11),
                                color: Colors.grey.shade900,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          SizedBox(height: _px(context, 2)),
                          LinearProgressIndicator(
                            value: isDone || isError || isPaused
                                ? (isDone ? 1.0 : (item.progress / 100).clamp(0.0, 1.0))
                                : (item.progress / 100).clamp(0.0, 1.0),
                            minHeight: 3,
                            backgroundColor: Colors.grey.shade300,
                            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                          ),
                          SizedBox(height: _px(context, 2)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  isDone
                                      ? 'Done'
                                      : isError
                                          ? 'Error'
                                          : isPaused
                                              ? '${item.progress}%'
                                              : '${item.progress}%',
                                  style: TextStyle(
                                    fontSize: _fs(context, 10),
                                    fontWeight: FontWeight.w600,
                                    color: statusColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isDownloading && onPause != null)
                                IconButton(
                                  icon: const Icon(Icons.pause_circle),
                                  iconSize: _fs(context, 18),
                                  tooltip: 'Pause',
                                  onPressed: onPause,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                )
                              else if ((isError || isPaused) && onResume != null)
                                IconButton(
                                  icon: Icon(isPaused ? Icons.play_circle : Icons.refresh, size: _fs(context, 18)),
                                  tooltip: isPaused ? 'Resume' : 'Retry',
                                  onPressed: onResume,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      color: Colors.grey.shade300,
      child: Icon(Icons.auto_stories_rounded, color: Colors.grey.shade600, size: 28),
    );
  }
}

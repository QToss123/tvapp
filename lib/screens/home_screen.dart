import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';
import '../routes.dart';
import '../widgets/book_card.dart';
import '../services/database_service.dart';
import '../utils/connectivity_helper.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLicenseActivated = false;
  bool _isLoading = true;
  bool _isLoadingBooks = false;
  String? _licenseStatusMessage;
  bool _isStorageConnected = true;
  String? _storageLocation;
  bool _hasInternet = false;
  Timer? _connectivityTimer;
  
  // Books loaded from API or fallback to dummy data
  List<Book> _books = [];
  
  _HomeScreenState();

  // Dummy books data - fallback for testing (kept for future use)
  // ignore: unused_field
  static const List<Book> _dummyBooks = [
    Book(
      title: 'Book 1',
      author: 'Author Name',
      progress: 30,
      thumbnail: 'https://covers.openlibrary.org/b/id/12887422-L.jpg',
      contentUrl: 'assets/books/book1',
    ),
    Book(
      title: 'Book 2',
      author: 'Another Author',
      progress: 55,
      thumbnail: 'https://covers.openlibrary.org/b/id/8739161-L.jpg',
      contentUrl: 'assets/books/book2',
    ),
    Book(
      title: 'The Pragmatic Programmer',
      author: 'Andrew Hunt',
      progress: 12,
      thumbnail: 'https://covers.openlibrary.org/b/id/10483108-L.jpg',
    ),
    Book(
      title: 'Clean Code',
      author: 'Robert Martin',
      progress: 75,
      thumbnail: 'https://covers.openlibrary.org/b/id/8739161-L.jpg',
    ),
    Book(
      title: 'Design Patterns',
      author: 'Gang of Four',
      progress: 40,
      thumbnail: 'https://covers.openlibrary.org/b/id/10483108-L.jpg',
    ),
    Book(
      title: 'The Lean Startup',
      author: 'Eric Ries',
      progress: 60,
      thumbnail: 'https://covers.openlibrary.org/b/id/12887422-L.jpg',
    ),
    Book(
      title: 'Sapiens',
      author: 'Yuval Noah Harari',
      progress: 25,
      thumbnail: 'https://covers.openlibrary.org/b/id/8739161-L.jpg',
    ),
    Book(
      title: 'Thinking Fast and Slow',
      author: 'Daniel Kahneman',
      progress: 50,
      thumbnail: 'https://covers.openlibrary.org/b/id/10483108-L.jpg',
    ),
    Book(
      title: 'The 7 Habits',
      author: 'Stephen Covey',
      progress: 80,
      thumbnail: 'https://covers.openlibrary.org/b/id/12887422-L.jpg',
    ),
    Book(
      title: 'Good to Great',
      author: 'Jim Collins',
      progress: 35,
      thumbnail: 'https://covers.openlibrary.org/b/id/8739161-L.jpg',
    ),
    Book(
      title: 'Atomic Habits',
      author: 'James Clear',
      progress: 45,
      thumbnail: 'https://covers.openlibrary.org/b/id/10483108-L.jpg',
    ),
    Book(
      title: 'The Power of Now',
      author: 'Eckhart Tolle',
      progress: 20,
      thumbnail: 'https://covers.openlibrary.org/b/id/12887422-L.jpg',
    ),
    Book(
      title: 'Rich Dad Poor Dad',
      author: 'Robert Kiyosaki',
      progress: 65,
      thumbnail: 'https://covers.openlibrary.org/b/id/8739161-L.jpg',
    ),
    Book(
      title: 'The Art of War',
      author: 'Sun Tzu',
      progress: 90,
      thumbnail: 'https://covers.openlibrary.org/b/id/10483108-L.jpg',
    ),
    Book(
      title: '1984',
      author: 'George Orwell',
      progress: 55,
      thumbnail: 'https://covers.openlibrary.org/b/id/12887422-L.jpg',
    ),
    Book(
      title: 'To Kill a Mockingbird',
      author: 'Harper Lee',
      progress: 70,
      thumbnail: 'https://covers.openlibrary.org/b/id/8739161-L.jpg',
    ),
    Book(
      title: 'The Great Gatsby',
      author: 'F. Scott Fitzgerald',
      progress: 40,
      thumbnail: 'https://covers.openlibrary.org/b/id/10483108-L.jpg',
    ),
    Book(
      title: 'Pride and Prejudice',
      author: 'Jane Austen',
      progress: 60,
      thumbnail: 'https://covers.openlibrary.org/b/id/12887422-L.jpg',
    ),
    Book(
      title: 'The Catcher in the Rye',
      author: 'J.D. Salinger',
      progress: 30,
      thumbnail: 'https://covers.openlibrary.org/b/id/8739161-L.jpg',
    ),
    Book(
      title: 'Lord of the Flies',
      author: 'William Golding',
      progress: 50,
      thumbnail: 'https://covers.openlibrary.org/b/id/10483108-L.jpg',
    ),
    Book(
      title: 'The Hobbit',
      author: 'J.R.R. Tolkien',
      progress: 85,
      thumbnail: 'https://covers.openlibrary.org/b/id/12887422-L.jpg',
    ),
    Book(
      title: 'Harry Potter',
      author: 'J.K. Rowling',
      progress: 95,
      thumbnail: 'https://covers.openlibrary.org/b/id/8739161-L.jpg',
    ),
    Book(
      title: 'The Alchemist',
      author: 'Paulo Coelho',
      progress: 75,
      thumbnail: 'https://covers.openlibrary.org/b/id/10483108-L.jpg',
    ),
    Book(
      title: 'The Kite Runner',
      author: 'Khaled Hosseini',
      progress: 55,
      thumbnail: 'https://covers.openlibrary.org/b/id/12887422-L.jpg',
    ),
    Book(
      title: 'The Book Thief',
      author: 'Markus Zusak',
      progress: 65,
      thumbnail: 'https://covers.openlibrary.org/b/id/8739161-L.jpg',
    ),
    Book(
      title: 'Life of Pi',
      author: 'Yann Martel',
      progress: 45,
      thumbnail: 'https://covers.openlibrary.org/b/id/10483108-L.jpg',
    ),
    Book(
      title: 'The Fault in Our Stars',
      author: 'John Green',
      progress: 35,
      thumbnail: 'https://covers.openlibrary.org/b/id/12887422-L.jpg',
    ),
    Book(
      title: 'Gone Girl',
      author: 'Gillian Flynn',
      progress: 80,
      thumbnail: 'https://covers.openlibrary.org/b/id/8739161-L.jpg',
    ),
    Book(
      title: 'The Girl on the Train',
      author: 'Paula Hawkins',
      progress: 60,
      thumbnail: 'https://covers.openlibrary.org/b/id/10483108-L.jpg',
    ),
    Book(
      title: 'The Da Vinci Code',
      author: 'Dan Brown',
      progress: 70,
      thumbnail: 'https://covers.openlibrary.org/b/id/12887422-L.jpg',
    ),
  ];

  String _query = '';
  final FocusNode _searchFocusNode = FocusNode();
  bool _searchEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkLicenseStatus();
    _checkConnectivity();
    // Check every 30s (was 6s) to avoid repeated DNS lookups and release APK issues
    _connectivityTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkConnectivity());
  }

  Future<void> _checkConnectivity() async {
    try {
      final connected = await ConnectivityHelper.hasInternetConnection();
      if (mounted) {
        setState(() => _hasInternet = connected);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hasInternet = false);
      }
    }
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    _connectivityTimer = null;
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLicenseActivated && _books.isNotEmpty) {
      // Defer so first frame paints; avoids bookshelf freeze on return to screen
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _checkStorageConnection().then((connected) {
          if (mounted) {
            setState(() => _isStorageConnected = connected);
            if (!connected) _checkLicenseStatus();
          }
        });
      });
    }
  }

  /// Loads books from local database.
  /// [storageAlreadyChecked] if true, skips storage check (caller already did it).
  Future<void> _loadBooks({bool? storageAlreadyChecked}) async {
    if (!_isLicenseActivated) {
      return;
    }

    if (mounted) setState(() => _isLoadingBooks = true);
    await Future.delayed(Duration.zero); // Let loading indicator paint

    try {
      final storageConnected = storageAlreadyChecked ?? await _checkStorageConnection();
      if (!storageConnected) {
        if (mounted) {
          setState(() {
            _isStorageConnected = false;
            _isLoadingBooks = false;
          });
          _checkLicenseStatus();
        }
        return;
      }

      final books = await DatabaseService.getAllBooks();
      // No history for reader: show all books with zero progress
      final booksNoHistory = books.map((b) => Book(
        title: b.title,
        author: b.author,
        progress: 0,
        thumbnail: b.thumbnail,
        thumbnailLocalPath: b.thumbnailLocalPath,
        contentUrl: b.contentUrl,
        encBookId: b.encBookId,
        encBookPath: b.encBookPath,
        encKeyB64: b.encKeyB64,
        encNonceB64: b.encNonceB64,
      )).toList();

      if (mounted) {
        setState(() {
          _books = booksNoHistory;
          _isStorageConnected = true;
          _isLoadingBooks = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _books = [];
          _isLoadingBooks = false;
        });
      }
    }
  }

  /// Checks if the configured storage device is connected and accessible
  Future<bool> _checkStorageConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final storageLocation = prefs.getString('storageLocation');
    
    if (storageLocation == null || 
        storageLocation.isEmpty || 
        storageLocation == 'Not selected') {
      return true; // No storage configured, skip check
    }
    
    _storageLocation = storageLocation;
    
    try {
      final storageDir = Directory(storageLocation);
      
      // Check if directory exists
      if (!await storageDir.exists()) {
        return false;
      }
      
      // Try to list directory to verify accessibility
      try {
        await storageDir.list().first.timeout(const Duration(milliseconds: 1000));
        return true;
      } catch (e) {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  Future<void> _checkLicenseStatus() async {
    
    final prefs = await SharedPreferences.getInstance();
    final licenseNumber = prefs.getString('licenseNumber') ?? '';
    final isActivated = prefs.getBool('licenseActivated') ?? false;
    final expiryDateStr = prefs.getString('licenseExpiryDate') ?? '';
    final syncCompleted = prefs.getBool('syncCompleted') ?? false;

    bool isValid = false;
    String? statusMessage;
    
    // Check storage connection if sync is completed
    bool storageConnected = true;
    if (syncCompleted) {
      storageConnected = await _checkStorageConnection();
      setState(() {
        _isStorageConnected = storageConnected;
      });
      
      if (!storageConnected) {
        isValid = false;
        statusMessage = 'Storage device not connected. Please connect the configured storage device to access your books.';
      }
    }
    
    // Check if license is activated
    if (licenseNumber.isNotEmpty && isActivated) {
      // License is activated, now check if it's valid
      bool licenseExpired = false;
      
      // Check expiry date if provided
      if (expiryDateStr.isNotEmpty) {
        try {
          final expiryDate = DateTime.parse(expiryDateStr);
          final now = DateTime.now();
          if (now.isAfter(expiryDate)) {
            // License has expired - deactivate it
            await prefs.setBool('licenseActivated', false);
            isValid = false;
            licenseExpired = true;
            statusMessage = 'Your license has expired. Please renew your license.';
          }
        } catch (e) {
          // Invalid date format - but don't block access, just log warning
          // Continue with validation
        }
      } else {
        // Expiry date not set - don't block access, just allow it
        // This can happen if activation API didn't return expiry date
      }
      
      // Only check sync and storage if license is not expired
      if (!licenseExpired) {
        // License is valid, check if sync is completed
        if (!syncCompleted) {
          isValid = false;
          statusMessage = 'License activated. Please complete configuration and sync books to continue.';
        } else if (!storageConnected) {
          isValid = false;
          // Status message already set above
        } else {
          isValid = true;
        }
      }
    } else {
      statusMessage = licenseNumber.isEmpty
          ? 'Please activate your license in Settings.'
          : null;
    }
    
    
    setState(() {
      _isLicenseActivated = isValid;
      _licenseStatusMessage = statusMessage;
      _isLoading = false;
    });

    // Load books from database if license is activated AND sync is completed
    if (isValid && syncCompleted) {
      _loadBooks(storageAlreadyChecked: storageConnected);
    } else {
      // Clear books if license is not valid or sync not completed
      setState(() {
        _books = [];
      });
    }
    
  }

  bool _canSync() {
    return _isLicenseActivated &&
        _storageLocation != null &&
        _storageLocation!.isNotEmpty &&
        _storageLocation != 'Not selected';
  }

  Future<void> _openDownloadPanel() async {
    if (!mounted) return;
    // Re-check internet so download is disabled when offline (e.g. Windows DNS cache)
    final hasInternet = await ConnectivityHelper.hasInternetConnection();
    if (mounted && !hasInternet) {
      setState(() => _hasInternet = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Internet connection required to download books.'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.pushNamed(context, AppRoutes.sync);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Show empty state if license is not activated or storage not connected
    if (!_isLicenseActivated) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('WebBooks Settings'),
          actions: [
            IconButton(
              tooltip: _hasInternet ? 'Settings' : 'Internet connection required',
              icon: Icon(Icons.settings, color: _hasInternet ? null : Colors.grey),
              onPressed: _hasInternet
                  ? () async {
                      await Future.delayed(const Duration(milliseconds: 120));
                      if (!mounted) return;
                      await Navigator.pushNamed(context, AppRoutes.settings);
                      if (mounted) {
                        _checkConnectivity();
                        await _checkLicenseStatus();
                        if (_isLicenseActivated) await _loadBooks();
                      }
                    }
                  : null,
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  !_isStorageConnected && _licenseStatusMessage?.contains('Storage device') == true
                      ? Icons.usb_off
                      : Icons.lock_outline,
                  size: 80,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 24),
                Text(
                  _licenseStatusMessage ?? 'Please activate the licence first to download books',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (!_isStorageConnected && _licenseStatusMessage?.contains('Storage device') == true) ...[
                  Text(
                    'Configured storage location: ${_storageLocation ?? "Not available"}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          // Retry checking storage connection
                          await _checkLicenseStatus();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        onPressed: _hasInternet
                            ? () async {
                                await Future.delayed(const Duration(milliseconds: 120));
                                if (!mounted) return;
                                await Navigator.pushNamed(context, AppRoutes.settings);
                                if (mounted) {
                                  _checkConnectivity();
                                  await _checkLicenseStatus();
                                  if (_isLicenseActivated) await _loadBooks();
                                }
                              }
                            : null,
                        icon: Icon(Icons.settings, color: _hasInternet ? null : Colors.grey),
                        label: const Text('Settings'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    _licenseStatusMessage != null
                        ? 'Go to Settings to update your license'
                        : 'Go to Settings to enter and activate your license number',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (!_hasInternet) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Internet connection required for Settings',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.orange.shade700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _hasInternet
                        ? () async {
                            await Future.delayed(const Duration(milliseconds: 120));
                            if (!mounted) return;
                            await Navigator.pushNamed(context, AppRoutes.settings);
                            if (mounted) {
                              _checkConnectivity();
                              await _checkLicenseStatus();
                              if (_isLicenseActivated) await _loadBooks();
                            }
                          }
                          : null,
                    icon: Icon(Icons.settings, color: _hasInternet ? null : Colors.grey),
                    label: const Text('Go to Settings'),
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

    // Show books if license is activated. Only show books with contentUrl
    // (file_path) so we never open reader without a loadable source.
    final filtered = _books
        .where((b) =>
            (b.contentUrl != null && b.contentUrl!.isNotEmpty) &&
            (b.title.toLowerCase().contains(_query.toLowerCase()) ||
                b.author.toLowerCase().contains(_query.toLowerCase())))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('WebBooks'),
        actions: [
          IconButton(
            tooltip: _hasInternet ? 'Settings' : 'Internet connection required',
            icon: Icon(Icons.settings, color: _hasInternet ? null : Colors.grey),
            onPressed: _hasInternet
                ? () async {
                    await Future.delayed(const Duration(milliseconds: 120));
                    if (!mounted) return;
                    await Navigator.pushNamed(context, AppRoutes.settings);
                    if (mounted) {
                      _checkConnectivity();
                      await _checkLicenseStatus();
                      if (_isLicenseActivated) {
                        await _loadBooks();
                      }
                    }
                  }
                : null,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    enabled: _searchEnabled,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: _searchEnabled
                          ? 'Search books or authors...'
                          : 'Press search to type...',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) async {
                      setState(() => _query = v);
                      if (v.isNotEmpty) {
                        // Search in database
                        try {
                          final filtered = await DatabaseService.searchBooks(v);
                          setState(() {
                            _books = filtered;
                          });
                        } catch (e) {
                          // Keep current books on error
                        }
                      } else {
                        // Reload all books
                        _loadBooks();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: _searchEnabled ? 'Disable search' : 'Enable search',
                  icon: Icon(_searchEnabled ? Icons.close : Icons.search),
                  onPressed: () {
                    setState(() => _searchEnabled = !_searchEnabled);
                    if (_searchEnabled) {
                      _searchFocusNode.requestFocus();
                    } else {
                      _searchFocusNode.unfocus();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoadingBooks
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            _books.isEmpty
                                ? 'No WebBooks found.'
                                : 'No WebBooks with downloaded content.\nComplete sync to download.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: MediaQuery.sizeOf(context).width >= 600 ? 6 : 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: MediaQuery.sizeOf(context).width >= 600 ? 0.58 : 0.52,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => BookCard(book: filtered[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

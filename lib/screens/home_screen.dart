import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';
import '../routes.dart';
import '../widgets/book_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLicenseActivated = false;
  bool _isLoading = true;
  String? _licenseStatusMessage;
  
  // Dummy books data - 30 books for testing
  final List<Book> _books = const [
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

  @override
  void initState() {
    super.initState();
    _checkLicenseStatus();
  }

  Future<void> _checkLicenseStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final licenseNumber = prefs.getString('licenseNumber') ?? '';
    final isActivated = prefs.getBool('licenseActivated') ?? false;
    final expiryDateStr = prefs.getString('licenseExpiryDate') ?? '';
    
    bool isValid = false;
    String? statusMessage;
    
    // Check if license is activated
    if (licenseNumber.isNotEmpty && isActivated) {
      // Check expiry date
      if (expiryDateStr.isNotEmpty) {
        try {
          final expiryDate = DateTime.parse(expiryDateStr);
          final now = DateTime.now();
          if (now.isAfter(expiryDate)) {
            // License has expired - deactivate it
            await prefs.setBool('licenseActivated', false);
            isValid = false;
            statusMessage = 'Your license has expired. Please renew your license.';
          } else {
            isValid = true;
          }
        } catch (e) {
          // Invalid date format
          isValid = false;
          statusMessage = 'Invalid license expiry date. Please update in Settings.';
        }
      } else {
        isValid = false;
        statusMessage = 'License expiry date is missing. Please update in Settings.';
      }
    } else {
      statusMessage = null; // Default message for no license
    }
    
    setState(() {
      _isLicenseActivated = isValid;
      _licenseStatusMessage = statusMessage;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Show empty state if license is not activated
    if (!_isLicenseActivated) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Bookshelf'),
          actions: [
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings),
              onPressed: () async {
                final result = await Navigator.pushNamed(context, AppRoutes.settings);
                // Reload license status when returning from settings
                if (result == true || mounted) {
                  _checkLicenseStatus();
                }
              },
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
                  Icons.lock_outline,
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
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.pushNamed(context, AppRoutes.settings);
                    // Reload license status when returning from settings
                    if (result == true || mounted) {
                      _checkLicenseStatus();
                    }
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('Go to Settings'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Show books if license is activated
    final filtered = _books
        .where((b) =>
            b.title.toLowerCase().contains(_query.toLowerCase()) ||
            b.author.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookshelf'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final result = await Navigator.pushNamed(context, AppRoutes.settings);
              // Reload license status when returning from settings
              if (result == true || mounted) {
                _checkLicenseStatus();
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search books or authors...',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No books found.'))
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 10,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.5,
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

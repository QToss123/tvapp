import 'package:flutter/material.dart';
import '../models/book.dart';
import '../routes.dart';
import '../widgets/book_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<Book> _books = const [
    Book(
      title: 'Book 1',
      author: 'Author Name',
      progress: 30,
      thumbnail: 'https://covers.openlibrary.org/b/id/12887422-L.jpg',
      contentUrl: 'assets/books/book1', // Folder path - automatically loads index.html
    ),
    Book(
      title: 'Book 2',
      author: 'Another Author',
      progress: 55,
      thumbnail: 'https://covers.openlibrary.org/b/id/8739161-L.jpg',
      contentUrl: 'assets/books/book2', // Folder path - automatically loads index.html
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
  ];

  String _query = '';

  @override
  Widget build(BuildContext context) {
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
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
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

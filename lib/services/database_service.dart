import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../models/book.dart';

/// Database service for storing books locally
class DatabaseService {
  static Database? _database;
  static const String _databaseName = 'books.db';
  static const int _databaseVersion = 3;
  
  static const String _tableBooks = 'books';
  
  // Book table columns
  static const String _colId = 'id';
  static const String _colTitle = 'title';
  static const String _colAuthor = 'author';
  static const String _colProgress = 'progress';
  static const String _colThumbnail = 'thumbnail';
  static const String _colContentUrl = 'content_url';
  static const String _colFilePath = 'file_path';
  static const String _colEncBookId = 'enc_book_id';
  static const String _colEncBookPath = 'enc_book_path';
  static const String _colEncKeyB64 = 'enc_key_b64';
  static const String _colEncNonceB64 = 'enc_nonce_b64';
  static const String _colCourseId = 'course_id';
  static const String _colSyncedAt = 'synced_at';
  static const String _colCreatedAt = 'created_at';

  /// Gets the database instance
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initializes the database
  static Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final dbPath = path.join(documentsDirectory.path, _databaseName);
    
    return await openDatabase(
      dbPath,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Creates the database tables
  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableBooks (
        $_colId INTEGER PRIMARY KEY AUTOINCREMENT,
        $_colCourseId INTEGER,
        $_colTitle TEXT NOT NULL,
        $_colAuthor TEXT NOT NULL,
        $_colProgress INTEGER DEFAULT 0,
        $_colThumbnail TEXT,
        $_colContentUrl TEXT,
        $_colFilePath TEXT,
        $_colEncBookId TEXT,
        $_colEncKeyB64 TEXT,
        $_colEncNonceB64 TEXT,
        $_colSyncedAt INTEGER,
        $_colCreatedAt INTEGER NOT NULL
      )
    ''');
    
    // Create index for faster searches
    await db.execute('''
      CREATE INDEX idx_books_title ON $_tableBooks($_colTitle)
    ''');
    await db.execute('''
      CREATE INDEX idx_books_author ON $_tableBooks($_colAuthor)
    ''');
  }

  /// Upgrades the database schema
  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle database upgrades here
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE $_tableBooks ADD COLUMN $_colEncBookId TEXT');
      await db.execute('ALTER TABLE $_tableBooks ADD COLUMN $_colEncKeyB64 TEXT');
      await db.execute('ALTER TABLE $_tableBooks ADD COLUMN $_colEncNonceB64 TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE $_tableBooks ADD COLUMN $_colEncBookPath TEXT');
    }
  }

  /// Inserts a book into the database
  static Future<int> insertBook(Book book, {int? courseId, String? filePath}) async {
    final db = await database;
    
    // Preserve created_at if updating existing book
    int? createdAt;
    if (courseId != null) {
      final existing = await db.query(
        _tableBooks,
        columns: [_colCreatedAt],
        where: '$_colCourseId = ?',
        whereArgs: [courseId],
      );
      if (existing.isNotEmpty) {
        createdAt = existing[0][_colCreatedAt] as int?;
      }
    }
    
    final bookMap = {
      _colCourseId: courseId,
      _colTitle: book.title,
      _colAuthor: book.author,
      _colProgress: book.progress,
      _colThumbnail: book.thumbnail,
      _colContentUrl: book.contentUrl,
      _colFilePath: filePath,
      _colEncBookId: book.encBookId,
      _colEncBookPath: book.encBookPath,
      _colEncKeyB64: book.encKeyB64,
      _colEncNonceB64: book.encNonceB64,
      _colSyncedAt: DateTime.now().millisecondsSinceEpoch,
      _colCreatedAt: createdAt ?? DateTime.now().millisecondsSinceEpoch,
    };

    // Check if book already exists by course_id or content_url
    if (courseId != null) {
      final existing = await db.query(
        _tableBooks,
        where: '$_colCourseId = ?',
        whereArgs: [courseId],
      );
      if (existing.isNotEmpty) {
        // Update existing book
        debugPrint('📝 Updating book in database: courseId=$courseId, title="${book.title}", filePath=$filePath');
        final rowsAffected = await db.update(
          _tableBooks,
          bookMap,
          where: '$_colCourseId = ?',
          whereArgs: [courseId],
        );
        debugPrint('✅ Updated $rowsAffected row(s) for courseId=$courseId');
        return rowsAffected;
      }
    }

    debugPrint('➕ Inserting new book: courseId=$courseId, title="${book.title}", filePath=$filePath');
    final id = await db.insert(_tableBooks, bookMap);
    debugPrint('✅ Inserted book with id=$id');
    return id;
  }

  /// Gets all books from the database
  static Future<List<Book>> getAllBooks() async {
    try {
      debugPrint('🔍 [DATABASE] Starting getAllBooks() query...');
      final db = await database;
      
      final List<Map<String, dynamic>> maps = await db.query(
        _tableBooks,
        orderBy: '$_colCreatedAt DESC',
      );

      debugPrint('📚 [DATABASE] getAllBooks: Found ${maps.length} books in database');
      
      if (maps.isEmpty) {
        debugPrint('⚠️ [DATABASE] No books found in database! Table might be empty.');
        return [];
      }

      final books = List.generate(maps.length, (i) {
        // Prioritize file_path over content_url for downloaded books
        String? contentUrl = maps[i][_colFilePath];
        if (contentUrl == null || contentUrl.isEmpty) {
          contentUrl = maps[i][_colContentUrl];
        }
        
        final title = maps[i][_colTitle] ?? 'Untitled';
        final courseId = maps[i][_colCourseId];
        final author = maps[i][_colAuthor] ?? 'Unknown';
        final thumbnail = maps[i][_colThumbnail];
        final filePath = maps[i][_colFilePath];
        final contentUrlRaw = maps[i][_colContentUrl];
        final encBookId = maps[i][_colEncBookId];
        final encKeyB64 = maps[i][_colEncKeyB64];
        final encNonceB64 = maps[i][_colEncNonceB64];
        
        debugPrint('📖 [DATABASE] Book $i:');
        debugPrint('   - courseId: $courseId');
        debugPrint('   - title: "$title"');
        debugPrint('   - author: "$author"');
        debugPrint('   - thumbnail: $thumbnail');
        debugPrint('   - filePath (raw): $filePath');
        debugPrint('   - contentUrl (raw): $contentUrlRaw');
        debugPrint('   - final contentUrl: $contentUrl');
        debugPrint('   - encBookId: $encBookId');
        debugPrint('   - encKeyB64: ${encKeyB64 != null ? '***' : 'null'}');
        debugPrint('   - encNonceB64: ${encNonceB64 != null ? '***' : 'null'}');
        
        // Ensure file:// protocol for local files
        if (contentUrl != null && 
            contentUrl.isNotEmpty && 
            !contentUrl.startsWith('http') && 
            !contentUrl.startsWith('file://') &&
            !contentUrl.startsWith('assets/')) {
          // If it's a local file path, ensure it has file:// protocol
          if (contentUrl.startsWith('/')) {
            contentUrl = 'file://$contentUrl';
          } else {
            contentUrl = 'file:///$contentUrl';
          }
          debugPrint('   - contentUrl (after protocol fix): $contentUrl');
        }
        
        return Book(
          title: title,
          author: author,
          progress: maps[i][_colProgress] ?? 0,
          thumbnail: thumbnail,
          contentUrl: contentUrl,
          encBookId: encBookId as String?,
          encBookPath: maps[i][_colEncBookPath] as String?,
          encKeyB64: encKeyB64 as String?,
          encNonceB64: encNonceB64 as String?,
        );
      });

      debugPrint('✅ [DATABASE] getAllBooks: Successfully converted ${books.length} books');
      return books;
    } catch (e, stackTrace) {
      debugPrint('❌ [DATABASE] Error in getAllBooks: $e');
      debugPrint('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Gets books by search query
  static Future<List<Book>> searchBooks(String query) async {
    try {
      debugPrint('🔍 [DATABASE] Starting searchBooks() query: "$query"');
      final db = await database;
      final searchTerm = '%$query%';
      
      final List<Map<String, dynamic>> maps = await db.query(
        _tableBooks,
        where: '$_colTitle LIKE ? OR $_colAuthor LIKE ?',
        whereArgs: [searchTerm, searchTerm],
        orderBy: '$_colCreatedAt DESC',
      );

      debugPrint('📚 [DATABASE] searchBooks: Found ${maps.length} books matching "$query"');
      
      if (maps.isEmpty) {
        debugPrint('⚠️ [DATABASE] No books found matching search query: "$query"');
        return [];
      }

      return List.generate(maps.length, (i) {
        // Prioritize file_path over content_url for downloaded books
        String? contentUrl = maps[i][_colFilePath];
        if (contentUrl == null || contentUrl.isEmpty) {
          contentUrl = maps[i][_colContentUrl];
        }
        final encBookId = maps[i][_colEncBookId];
        final encKeyB64 = maps[i][_colEncKeyB64];
        final encNonceB64 = maps[i][_colEncNonceB64];
        
        final title = maps[i][_colTitle] ?? 'Untitled';
        debugPrint('📖 [DATABASE] Search result $i: "$title"');
        
        // Ensure file:// protocol for local files
        if (contentUrl != null && 
            contentUrl.isNotEmpty && 
            !contentUrl.startsWith('http') && 
            !contentUrl.startsWith('file://') &&
            !contentUrl.startsWith('assets/')) {
          // If it's a local file path, ensure it has file:// protocol
          if (contentUrl.startsWith('/')) {
            contentUrl = 'file://$contentUrl';
          } else {
            contentUrl = 'file:///$contentUrl';
          }
        }
        
        return Book(
          title: maps[i][_colTitle],
          author: maps[i][_colAuthor] ?? 'Unknown',
          progress: maps[i][_colProgress] ?? 0,
          thumbnail: maps[i][_colThumbnail],
          contentUrl: contentUrl,
          encBookId: encBookId as String?,
          encBookPath: maps[i][_colEncBookPath] as String?,
          encKeyB64: encKeyB64 as String?,
          encNonceB64: encNonceB64 as String?,
        );
      });
    } catch (e, stackTrace) {
      debugPrint('❌ [DATABASE] Error in searchBooks: $e');
      debugPrint('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Gets the raw file path for a book by enc_book_id (for "already downloaded" checks).
  /// Returns path if we have this book and the file exists on disk.
  static Future<String?> getFilePathByEncBookId(String encBookId) async {
    final db = await database;
    final maps = await db.query(
      _tableBooks,
      columns: [_colFilePath, _colContentUrl],
      where: '$_colEncBookId = ?',
      whereArgs: [encBookId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final filePath = maps[0][_colFilePath] as String?;
    if (filePath != null && filePath.isNotEmpty) {
      if (await File(filePath).exists()) return filePath;
    }
    final contentUrl = maps[0][_colContentUrl] as String?;
    if (contentUrl == null || contentUrl.isEmpty) return null;
    if (contentUrl.startsWith('file://')) {
      final uri = Uri.parse(contentUrl);
      var p = uri.path;
      if (Platform.isWindows && p.length >= 3 && p.startsWith('/') && p[2] == ':') {
        p = p.substring(1);
      }
      final pathStr = Platform.isWindows ? p.replaceAll('/', path.separator) : p;
      if (await File(pathStr).exists()) return pathStr;
    }
    return null;
  }

  /// Gets the raw file path for a book by course ID (for "already downloaded" checks).
  static Future<String?> getFilePathByCourseId(int courseId) async {
    final db = await database;
    final maps = await db.query(
      _tableBooks,
      columns: [_colFilePath, _colContentUrl],
      where: '$_colCourseId = ?',
      whereArgs: [courseId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final filePath = maps[0][_colFilePath] as String?;
    if (filePath != null && filePath.isNotEmpty) return filePath;
    final contentUrl = maps[0][_colContentUrl] as String?;
    if (contentUrl == null || contentUrl.isEmpty) return null;
    if (contentUrl.startsWith('file://')) {
      final uri = Uri.parse(contentUrl);
      var p = uri.path;
      if (Platform.isWindows && p.length >= 3 && p.startsWith('/') && p[2] == ':') {
        p = p.substring(1);
      }
      return Platform.isWindows ? p.replaceAll('/', path.separator) : p;
    }
    return contentUrl;
  }

  /// Gets book by course ID
  static Future<Book?> getBookByCourseId(int courseId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableBooks,
      where: '$_colCourseId = ?',
      whereArgs: [courseId],
      limit: 1,
    );

    if (maps.isEmpty) return null;

    // Prioritize file_path over content_url for downloaded books
    String? contentUrl = maps[0][_colFilePath];
    if (contentUrl == null || contentUrl.isEmpty) {
      contentUrl = maps[0][_colContentUrl];
    }
    final encBookId = maps[0][_colEncBookId];
    final encKeyB64 = maps[0][_colEncKeyB64];
    final encNonceB64 = maps[0][_colEncNonceB64];
    
    // Ensure file:// protocol for local files
    if (contentUrl != null && 
        contentUrl.isNotEmpty && 
        !contentUrl.startsWith('http') && 
        !contentUrl.startsWith('file://') &&
        !contentUrl.startsWith('assets/')) {
      // If it's a local file path, ensure it has file:// protocol
      if (contentUrl.startsWith('/')) {
        contentUrl = 'file://$contentUrl';
      } else {
        contentUrl = 'file:///$contentUrl';
      }
    }

    return Book(
      title: maps[0][_colTitle],
      author: maps[0][_colAuthor],
      progress: maps[0][_colProgress] ?? 0,
      thumbnail: maps[0][_colThumbnail],
      contentUrl: contentUrl,
      encBookId: encBookId as String?,
      encBookPath: maps[0][_colEncBookPath] as String?,
      encKeyB64: encKeyB64 as String?,
      encNonceB64: encNonceB64 as String?,
    );
  }

  /// Gets book by file path (prefers file_path, falls back to content_url)
  static Future<Book?> getBookByFilePath(String filePath) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableBooks,
      where: '$_colFilePath = ?',
      whereArgs: [filePath],
      limit: 1,
    );

    Map<String, dynamic>? row;
    if (maps.isNotEmpty) {
      row = maps[0];
    } else {
      final fileUrl = filePath.startsWith('file://') ? filePath : 'file://$filePath';
      final List<Map<String, dynamic>> urlMaps = await db.query(
        _tableBooks,
        where: '$_colContentUrl = ?',
        whereArgs: [fileUrl],
        limit: 1,
      );
      if (urlMaps.isNotEmpty) {
        row = urlMaps[0];
      }
    }

    if (row == null) return null;

    // Prioritize file_path over content_url for downloaded books
    String? contentUrl = row[_colFilePath];
    if (contentUrl == null || contentUrl.isEmpty) {
      contentUrl = row[_colContentUrl];
    }
    final encBookId = row[_colEncBookId];
    final encKeyB64 = row[_colEncKeyB64];
    final encNonceB64 = row[_colEncNonceB64];

    // Ensure file:// protocol for local files
    if (contentUrl != null &&
        contentUrl.isNotEmpty &&
        !contentUrl.startsWith('http') &&
        !contentUrl.startsWith('file://') &&
        !contentUrl.startsWith('assets/')) {
      if (contentUrl.startsWith('/')) {
        contentUrl = 'file://$contentUrl';
      } else {
        contentUrl = 'file:///$contentUrl';
      }
    }

    return Book(
      title: row[_colTitle],
      author: row[_colAuthor],
      progress: row[_colProgress] ?? 0,
      thumbnail: row[_colThumbnail],
      contentUrl: contentUrl,
      encBookId: encBookId as String?,
      encBookPath: row[_colEncBookPath] as String?,
      encKeyB64: encKeyB64 as String?,
      encNonceB64: encNonceB64 as String?,
    );
  }

  /// Logs all rows in the books table (for debugging)
  static Future<void> logAllBooks() async {
    try {
      final db = await database;
      final rows = await db.query(_tableBooks, orderBy: '$_colCreatedAt DESC');
      debugPrint('📋 [DATABASE] books table: ${rows.length} row(s)');
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        debugPrint('Row $i: ${row.toString()}');
      }
    } catch (e) {
      debugPrint('❌ [DATABASE] Failed to log books table: $e');
    }
  }

  /// Updates book progress
  static Future<int> updateBookProgress(String contentUrl, int progress) async {
    final db = await database;
    return await db.update(
      _tableBooks,
      {_colProgress: progress},
      where: '$_colContentUrl = ?',
      whereArgs: [contentUrl],
    );
  }

  /// Deletes a book from the database
  static Future<int> deleteBook(int id) async {
    final db = await database;
    return await db.delete(
      _tableBooks,
      where: '$_colId = ?',
      whereArgs: [id],
    );
  }

  /// Clears all books from the database
  static Future<int> clearAllBooks() async {
    final db = await database;
    return await db.delete(_tableBooks);
  }

  /// Gets book count
  static Future<int> getBookCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM $_tableBooks');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Checks database status and logs detailed information
  /// Returns a map with status information
  static Future<Map<String, dynamic>> checkDatabaseStatus() async {
    try {
      debugPrint('🔍 [DATABASE] ========== DATABASE STATUS CHECK ==========');
      
      final db = await database;
      
      // Get book count
      final count = await getBookCount();
      debugPrint('📊 [DATABASE] Total books in database: $count');
      
      if (count == 0) {
        debugPrint('⚠️ [DATABASE] Database is EMPTY - No books found!');
        debugPrint('📋 [DATABASE] This means:');
        debugPrint('   1. No sync has been performed yet');
        debugPrint('   2. Books were not saved during sync');
        debugPrint('   3. Database was cleared/reset');
        return {
          'hasData': false,
          'bookCount': 0,
          'books': <Map<String, dynamic>>[],
        };
      }
      
      // Get all books with full details
      final List<Map<String, dynamic>> allBooks = await db.query(
        _tableBooks,
        orderBy: '$_colCreatedAt DESC',
      );
      
      debugPrint('📚 [DATABASE] Detailed book information:');
      final List<Map<String, dynamic>> booksInfo = [];
      
      for (int i = 0; i < allBooks.length; i++) {
        final book = allBooks[i];
        final bookInfo = {
          'id': book[_colId],
          'courseId': book[_colCourseId],
          'title': book[_colTitle],
          'author': book[_colAuthor],
          'filePath': book[_colFilePath],
          'contentUrl': book[_colContentUrl],
          'thumbnail': book[_colThumbnail],
          'progress': book[_colProgress],
        };
        booksInfo.add(bookInfo);
        
        debugPrint('   Book ${i + 1}:');
        debugPrint('     - ID: ${book[_colId]}');
        debugPrint('     - Course ID: ${book[_colCourseId]}');
        debugPrint('     - Title: "${book[_colTitle]}"');
        debugPrint('     - Author: "${book[_colAuthor]}"');
        debugPrint('     - File Path: ${book[_colFilePath] ?? "NULL"}');
        debugPrint('     - Content URL: ${book[_colContentUrl] ?? "NULL"}');
        debugPrint('     - Thumbnail: ${book[_colThumbnail] ?? "NULL"}');
        debugPrint('     - Progress: ${book[_colProgress] ?? 0}%');
        debugPrint('     - Created: ${book[_colCreatedAt]}');
        debugPrint('     - Synced: ${book[_colSyncedAt] ?? "NULL"}');
        
        // Check if file path exists
        if (book[_colFilePath] != null && book[_colFilePath].toString().isNotEmpty) {
          try {
            final filePath = book[_colFilePath] as String;
            final file = File(filePath);
            final exists = await file.exists();
            debugPrint('     - File exists: $exists');
            if (!exists) {
              debugPrint('     ⚠️ File not found at path: $filePath');
            }
          } catch (e) {
            debugPrint('     ⚠️ Error checking file: $e');
          }
        } else {
          debugPrint('     ⚠️ No file path stored for this book');
        }
        debugPrint('');
      }
      
      // Count books with/without file paths
      final withPaths = allBooks.where((b) => 
        b[_colFilePath] != null && 
        b[_colFilePath].toString().isNotEmpty
      ).length;
      final withoutPaths = count - withPaths;
      
      debugPrint('📈 [DATABASE] Statistics:');
      debugPrint('   - Books with file paths: $withPaths');
      debugPrint('   - Books without file paths: $withoutPaths');
      
      debugPrint('✅ [DATABASE] ========== STATUS CHECK COMPLETE ==========');
      
      return {
        'hasData': true,
        'bookCount': count,
        'booksWithPaths': withPaths,
        'booksWithoutPaths': withoutPaths,
        'books': booksInfo,
      };
    } catch (e, stackTrace) {
      debugPrint('❌ [DATABASE] Error checking database status: $e');
      debugPrint('Stack trace: $stackTrace');
      return {
        'hasData': false,
        'error': e.toString(),
      };
    }
  }

  /// Scans folder for books (offline mode)
  static Future<List<Book>> scanFolderForBooks(String folderPath) async {
    final List<Book> books = [];
    
    try {
      final directory = Directory(folderPath);
      if (!await directory.exists()) {
        debugPrint('Directory does not exist: $folderPath');
        return books;
      }

      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          final lowerName = fileName.toLowerCase();
          
          // Check if it's a book file (ZIP or HTML)
          if (lowerName.endsWith('.zip') || 
              lowerName == 'index.html' || 
              lowerName.endsWith('.html')) {
            
            // Try to extract title from folder name
            final parentDir = entity.parent;
            final folderName = path.basename(parentDir.path);
            
            // Create book entry
            final bookUrl = entity.path.startsWith('/')
                ? 'file://${entity.path}'
                : 'file:///${entity.path}';
            
            final book = Book(
              title: folderName.replaceAll('_', ' ').replaceAll('-', ' '),
              author: 'Unknown Author',
              progress: 0,
              contentUrl: bookUrl,
            );
            
            books.add(book);
            
            // Save to database
            await insertBook(book, filePath: entity.path);
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning folder: $e');
    }
    
    return books;
  }

  /// Closes the database
  static Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}

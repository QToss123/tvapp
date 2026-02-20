import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/book.dart';
import 'database_service.dart';
import '../utils/decrypt_util.dart';
import '../utils/zip_handler.dart';

/// Pre-processes books in the background when the bookshelf loads.
/// Decrypts and unzips books one-by-one so they open quickly when clicked.
class BookPreprocessService {
  /// Converts file:// URL to native path (matches reading_screen logic).
  static String _fileUrlToPath(String fileUrl) {
    String normalizedUrl = fileUrl.trim();
    if (!normalizedUrl.contains('://')) {
      normalizedUrl = 'file://$normalizedUrl';
    }
    final uri = Uri.parse(normalizedUrl);
    var filePath = uri.path;
    if (Platform.isAndroid && filePath.isNotEmpty && !filePath.startsWith('/')) {
      filePath = '/$filePath';
    }
    if (Platform.isWindows) {
      filePath = filePath.replaceAll('/', path.separator);
    }
    return filePath;
  }

  /// Pre-processes books one by one in the background.
  /// Call after loading books on the bookshelf; runs without blocking UI.
  static void preprocessBooks(List<Book> books) {
    if (books.isEmpty) return;
    // Delay start so bookshelf renders first, then run in background
    Future.delayed(const Duration(milliseconds: 500), () => _processOneByOne(books));
  }

  static Future<void> _processOneByOne(List<Book> books) async {
    for (final book in books) {
      await Future.delayed(Duration.zero); // Yield so UI stays responsive
      try {
        await _preprocessOne(book);
      } catch (e, st) {
        debugPrint('[BookPreprocess] Preprocess failed for ${book.title}: $e\n$st');
      }
      // Delay between books to avoid blocking UI
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  static Future<void> _preprocessOne(Book book) async {
    await Future.delayed(Duration.zero); // Yield at start
    final contentUrl = book.contentUrl;
    if (contentUrl == null || contentUrl.isEmpty) return;
    if (!contentUrl.startsWith('file://')) return; // Only local files

    var filePath = _fileUrlToPath(contentUrl);
    final file = File(filePath);
    if (!await file.exists()) return;

    // Get encryption keys from DB or book
    final dbBook = await DatabaseService.getBookByFilePath(filePath);
    final encBookId = dbBook?.encBookId ?? book.encBookId;
    final encKeyB64 = dbBook?.encKeyB64 ?? book.encKeyB64;
    final encNonceB64 = dbBook?.encNonceB64 ?? book.encNonceB64;

    // Decrypt if encrypted
    final hasEncMeta = (encBookId != null && encBookId.isNotEmpty) ||
        (encKeyB64 != null && encKeyB64.isNotEmpty) ||
        (encNonceB64 != null && encNonceB64.isNotEmpty);

    if (hasEncMeta) {
      await Future.delayed(Duration.zero); // Yield before decrypt
      try {
        final result = await decryptBookFileIfNeeded(
          encryptedFilePath: filePath,
          encBookId: encBookId,
          encKeyB64: encKeyB64,
          encNonceB64: encNonceB64,
        );
        filePath = result.pathToUse;
      } catch (e, st) {
        debugPrint('[BookPreprocess] Decrypt failed for ${book.title}: $e\n$st');
        return;
      }
    }

    // Unzip if ZIP file
    if (ZipHandler.isZipFile(filePath)) {
      await Future.delayed(Duration.zero); // Yield before unzip
      try {
        await ZipHandler.processBookFileOffMain(filePath);
      } catch (e, st) {
        debugPrint('[BookPreprocess] Unzip failed for ${book.title}: $e\n$st');
      }
    }
  }
}

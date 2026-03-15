import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Clears decrypted book temp files when app exits (for security).
/// Extracted books are kept so reopening the same book is fast.
class TempCleanupService {
  /// Removes decrypted_books from app temp directory. Keeps extracted_books for faster reopen.
  static Future<void> clearBookTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final decryptedDir = Directory(path.join(tempDir.path, 'decrypted_books'));

      if (await decryptedDir.exists()) {
        await decryptedDir.delete(recursive: true);
      }
      // Do not delete extracted_books here — reuse on next open for much faster book opening
    } catch (e) {
      // Best-effort cleanup, ignore errors
    }
  }
}

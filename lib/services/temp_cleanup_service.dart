import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Clears decrypted and extracted book temp files when app exits (for security).
class TempCleanupService {
  /// Removes decrypted_books and extracted_books folders from app temp directory.
  static Future<void> clearBookTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final decryptedDir = Directory(path.join(tempDir.path, 'decrypted_books'));
      final extractedDir = Directory(path.join(tempDir.path, 'extracted_books'));

      if (await decryptedDir.exists()) {
        await decryptedDir.delete(recursive: true);
      }
      if (await extractedDir.exists()) {
        await extractedDir.delete(recursive: true);
      }
    } catch (e) {
      // Best-effort cleanup, ignore errors
    }
  }
}

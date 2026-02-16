import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../services/book_decryption_service.dart';

/// Util for decrypting book files on open. Uses per-book keys from DB; master key is fixed.
/// Call when user clicks on a book and the file is encrypted.

/// Result of [decryptBookFileIfNeeded].
class DecryptResult {
  /// Path to use for reading (decrypted path if decrypted, else original).
  final String pathToUse;
  /// Whether decryption was performed (or reused).
  final bool wasDecrypted;
  /// True if we reused an existing _decrypted.zip; false if we just decrypted.
  final bool reusedExisting;
  /// True if the decrypted file lives in app cache (internal storage).
  final bool storedInCache;

  const DecryptResult({
    required this.pathToUse,
    required this.wasDecrypted,
    required this.reusedExisting,
    required this.storedInCache,
  });
}

/// Returns the path where the decrypted file is stored in app cache (internal storage).
Future<String> decryptedPathFor({
  required String encryptedFilePath,
  required String encBookId,
}) async {
  final tempDir = await getTemporaryDirectory();
  final baseName = encBookId.isNotEmpty
      ? encBookId
      : path.basenameWithoutExtension(encryptedFilePath);
  final cacheDir = Directory(path.join(tempDir.path, 'decrypted_books'));
  if (!await cacheDir.exists()) {
    await cacheDir.create(recursive: true);
  }
  return path.join(cacheDir.path, '${baseName}_decrypted.zip');
}

/// Checks if the decrypted file already exists in app cache.
Future<bool> isDecryptedFileAvailable({
  required String encryptedFilePath,
  required String encBookId,
}) async {
  final decPath = await decryptedPathFor(
    encryptedFilePath: encryptedFilePath,
    encBookId: encBookId,
  );
  final f = File(decPath);
  final exists = await f.exists();
  if (exists) {
    final len = await f.length();
  }
  return exists;
}

/// Decrypts the book file when opened (on click). Reuses existing decrypted file if present.
/// Keys are unchanged: master key fixed, per-book encBookId/encKeyB64/encNonceB64 from DB.
///
/// Returns [DecryptResult.pathToUse] for the ZIP to unzip/open. Throws on missing keys or decrypt failure.
Future<DecryptResult> decryptBookFileIfNeeded({
  required String encryptedFilePath,
  required String? encBookId,
  required String? encKeyB64,
  required String? encNonceB64,
}) async {
  final hasKeys = encBookId != null && encBookId.isNotEmpty &&
      encKeyB64 != null && encKeyB64.isNotEmpty &&
      encNonceB64 != null && encNonceB64.isNotEmpty;

  if (!hasKeys) {
    throw Exception('Missing encryption keys for: $encryptedFilePath');
  }

  final file = File(encryptedFilePath);
  if (!await file.exists()) {
    throw Exception('Encrypted file not found: $encryptedFilePath');
  }

  final decryptedPath = await decryptedPathFor(
    encryptedFilePath: encryptedFilePath,
    encBookId: encBookId!,
  );
  final decryptedFile = File(decryptedPath);

  // Check if file already decrypted (reuse _decrypted.zip)
  final alreadyDecrypted = await decryptedFile.exists();
  if (alreadyDecrypted) {
    final len = await decryptedFile.length();
    return DecryptResult(
      pathToUse: decryptedPath,
      wasDecrypted: true,
      reusedExisting: true,
      storedInCache: true,
    );
  }

  await BookDecryptionService.decryptFileOnDisk(
    encryptedFilePath: encryptedFilePath,
    bookId: encBookId!,
    keyEncB64: encKeyB64!,
    keyNonceB64: encNonceB64!,
    outputFilePath: decryptedPath,
  );

  // Verify decrypted file exists and log
  final verify = File(decryptedPath);
  if (!await verify.exists()) {
    throw Exception('Decryption completed but decrypted file not found: $decryptedPath');
  }
  final decryptedSize = await verify.length();
  return DecryptResult(
    pathToUse: decryptedPath,
    wasDecrypted: true,
    reusedExisting: false,
    storedInCache: true,
  );
}

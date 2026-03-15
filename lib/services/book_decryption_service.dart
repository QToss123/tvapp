import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// Params for background isolate (must be top-level).
class DecryptParams {
  final String downloadUrl;
  final String bookId;
  final String keyEncB64;
  final String keyNonceB64;
  final String targetFilePath;

  const DecryptParams({
    required this.downloadUrl,
    required this.bookId,
    required this.keyEncB64,
    required this.keyNonceB64,
    required this.targetFilePath,
  });
}

/// Params for decrypt-on-open (file already on disk).
class DecryptOnDiskParams {
  final String encryptedFilePath;
  final String bookId;
  final String keyEncB64;
  final String keyNonceB64;
  final String outputFilePath;

  const DecryptOnDiskParams({
    required this.encryptedFilePath,
    required this.bookId,
    required this.keyEncB64,
    required this.keyNonceB64,
    required this.outputFilePath,
  });
}

/// Top-level entry for [compute]. Runs download+decrypt off main thread to avoid skipped frames.
Future<String> downloadAndDecryptBackground(DecryptParams p) async {
  return BookDecryptionService.downloadAndDecryptBook(
    downloadUrl: p.downloadUrl,
    bookId: p.bookId,
    keyEncB64: p.keyEncB64,
    keyNonceB64: p.keyNonceB64,
    targetFilePath: p.targetFilePath,
    onProgress: null,
  );
}

/// Top-level entry for [compute]. Decrypts an on-disk encrypted file.
Future<String> decryptOnDiskBackground(DecryptOnDiskParams p) async {
  return BookDecryptionService.decryptFileOnDisk(
    encryptedFilePath: p.encryptedFilePath,
    bookId: p.bookId,
    keyEncB64: p.keyEncB64,
    keyNonceB64: p.keyNonceB64,
    outputFilePath: p.outputFilePath,
  );
}

/// Service for downloading and decrypting encrypted books from the API.
/// Uses [cryptography] + [cryptography_flutter] for native AES-GCM (~50x faster on Android).
/// File size guard prevents OOM on large files (AES-GCM requires full ciphertext in memory).
class BookDecryptionService {
  /// Max size (bytes) for decryption - avoid OOM on low-memory devices (e.g. TV).
  static const int _maxDecryptFileSizeBytes = 150 * 1024 * 1024; // 150 MB

  static const String _masterKeyB64 =
      'p4wZbM9kqFv6QzQhM0xA2G9Pz0x0QnH2xX3B6YkJQzE=';

  static const _nonceLength = 12;
  static const _macLength = 16; // GCM 128-bit tag

  /// AES-GCM algorithm. Uses Flutter native (Android/iOS) when [cryptography_flutter] is used.
  static AesGcm get _aesGcm => AesGcm.with256bits(nonceLength: _nonceLength);

  /// Downloads the encrypted file from [downloadUrl], decrypts it using
  /// [bookId], [keyEncB64], [keyNonceB64], and saves to [targetFilePath].
  /// [onProgress] receives 0.0..1.0 (download only; decryption is fast).
  static Future<String> downloadAndDecryptBook({
    required String downloadUrl,
    required String bookId,
    required String keyEncB64,
    required String keyNonceB64,
    required String targetFilePath,
    void Function(double progress)? onProgress,
  }) async {
    final tempPath = await _downloadToFile(downloadUrl, onProgress);
    final tempFile = File(tempPath);
    final encryptedLength = await tempFile.length();
    if (encryptedLength > _maxDecryptFileSizeBytes) {
      try { await tempFile.delete(); } catch (_) {}
      throw Exception(
        'Downloaded file too large to decrypt on this device (${(encryptedLength / (1024 * 1024)).toStringAsFixed(1)} MB). Maximum supported: ${_maxDecryptFileSizeBytes ~/ (1024 * 1024)} MB.',
      );
    }

    final contentKey = await _decryptContentKey(
      keyEncB64: keyEncB64,
      keyNonceB64: keyNonceB64,
      bookId: bookId,
    );

    final encryptedBytes = await tempFile.readAsBytes();
    try {
      final decryptedBytes = await _decryptFileContent(
        encryptedData: encryptedBytes,
        contentKey: contentKey,
      );

      final file = File(targetFilePath);
      await file.parent.create(recursive: true);
      if (await file.exists()) await file.delete();
      await file.writeAsBytes(decryptedBytes);
      return targetFilePath;
    } finally {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }

  /// Decrypts an encrypted file already on disk and writes decrypted bytes to [outputFilePath].
  /// Format: 12-byte nonce + ciphertext + 16-byte MAC. Uses native AES-GCM when available.
  static Future<String> decryptFileOnDisk({
    required String encryptedFilePath,
    required String bookId,
    required String keyEncB64,
    required String keyNonceB64,
    required String outputFilePath,
  }) async {
    try {
      final encryptedFile = File(encryptedFilePath);
      if (!await encryptedFile.exists()) {
        throw Exception('Encrypted file not found: $encryptedFilePath');
      }
      final fileSize = await encryptedFile.length();
      if (fileSize > _maxDecryptFileSizeBytes) {
        throw Exception(
          'File too large to decrypt on this device (${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB). Maximum supported: ${_maxDecryptFileSizeBytes ~/ (1024 * 1024)} MB.',
        );
      }

      final encryptedBytes = await encryptedFile.readAsBytes();

      final contentKey = await _decryptContentKey(
        keyEncB64: keyEncB64,
        keyNonceB64: keyNonceB64,
        bookId: bookId,
      );

      final stopwatch = Stopwatch()..start();
      final decryptedBytes = await _decryptFileContent(
        encryptedData: encryptedBytes,
        contentKey: contentKey,
      );
      stopwatch.stop();

      final outFile = File(outputFilePath);
      await outFile.parent.create(recursive: true);
      if (await outFile.exists()) await outFile.delete();
      await outFile.writeAsBytes(decryptedBytes);
      return outputFilePath;
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Decryption failed: $e');
    }
  }

  /// Streams download to a temp file to avoid OOM.
  /// Uses Directory.systemTemp (no path_provider) so it works in compute() isolate.
  static Future<String> _downloadToFile(
    String url,
    void Function(double)? onProgress,
  ) async {
    final request = await http.Client().send(http.Request('GET', Uri.parse(url)));
    if (request.statusCode != 200) {
      throw Exception('Failed to download file: ${request.statusCode}');
    }
    final contentLength = request.contentLength ?? 0;
    final tempPath = path.join(
      Directory.systemTemp.path,
      'encrypted_book_${DateTime.now().millisecondsSinceEpoch}.bin',
    );
    final file = File(tempPath);
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in request.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0 && onProgress != null) {
          onProgress((received / contentLength).clamp(0.0, 1.0));
        }
      }
    } finally {
      await sink.close();
    }
    return tempPath;
  }

  static Future<Uint8List> _decryptContentKey({
    required String keyEncB64,
    required String keyNonceB64,
    required String bookId,
  }) async {
    try {
      final masterKey = base64.decode(_masterKeyB64);
      final encryptedKey = base64.decode(keyEncB64);
      final nonce = base64.decode(keyNonceB64);

      if (masterKey.length != 32) {
        throw Exception('Master key must be 32 bytes, got ${masterKey.length}');
      }
      if (nonce.length != _nonceLength) {
        throw Exception('Nonce must be $_nonceLength bytes, got ${nonce.length}');
      }

      final aad = utf8.encode('book_id:$bookId');
      final concatenated = Uint8List.fromList([...nonce, ...encryptedKey]);
      final secretBox = SecretBox.fromConcatenation(
        concatenated,
        nonceLength: _nonceLength,
        macLength: _macLength,
        copy: false,
      );
      final secretKey = SecretKey(masterKey);

      final decrypted = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
        aad: aad,
      );

      if (decrypted.length != 32) {
        throw Exception(
            'Decrypted content key must be 32 bytes, got ${decrypted.length}');
      }
      return Uint8List.fromList(decrypted);
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Content key decryption failed: $e');
    }
  }

  static Future<Uint8List> _decryptFileContent({
    required Uint8List encryptedData,
    required Uint8List contentKey,
    List<int> aad = const [],
  }) async {
    try {
      if (encryptedData.length < _nonceLength + _macLength) {
        throw Exception('Encrypted data too short');
      }
      final secretBox = SecretBox.fromConcatenation(
        encryptedData,
        nonceLength: _nonceLength,
        macLength: _macLength,
        copy: false,
      );
      final secretKey = SecretKey(contentKey);
      final decrypted = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
        aad: aad,
      );
      return Uint8List.fromList(decrypted);
    } catch (e) {
      _logDecrypt(
        'decryptFileContent failed',
        dataLength: encryptedData.length,
        error: e,
      );
      if (e is Exception) rethrow;
      throw Exception('File decryption failed: $e');
    }
  }

  /// Appends a line to decrypt_log.txt next to the running executable (for debugging MAC/decrypt errors).
  static void _logDecrypt(
    String message, {
    String? requestedPath,
    int? dataLength,
    Object? error,
  }) {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final logFile = File(path.join(exeDir.path, 'decrypt_log.txt'));
      final timestamp = DateTime.now().toIso8601String();
      final buffer = StringBuffer()
        ..writeln('---')
        ..writeln('$timestamp')
        ..writeln(message);
      if (requestedPath != null) buffer.writeln('path: $requestedPath');
      if (dataLength != null) buffer.writeln('size: $dataLength bytes');
      if (error != null) buffer.writeln('error: $error');
      buffer.writeln();
      logFile.writeAsStringSync(buffer.toString(), mode: FileMode.append);
    } catch (_) {}
  }

  /// Default max size for a single encrypted chapter/asset when decrypting on demand.
  /// Tuned for Android TV: moderate increase to support real books while controlling OOM risk.
  static int get maxPerFileDecryptBytes =>
      Platform.isAndroid ? 1024 * 1024 : 10 * 1024 * 1024; // 1 MB on Android, 10 MB elsewhere

  /// Higher cap for encrypted video assets (mp4/webm) which are usually larger than pages.
  static int get maxPerVideoDecryptBytes =>
      Platform.isAndroid ? 5 * 1024 * 1024 : 20 * 1024 * 1024; // 5 MB on Android, 20 MB elsewhere

  /// Slightly higher cap for animation videos folder, which often contains bigger MP4 assets.
  static int get maxPerAnimationVideoDecryptBytes =>
      Platform.isAndroid ? 8 * 1024 * 1024 : 24 * 1024 * 1024; // 8 MB on Android, 24 MB elsewhere

  /// Per-path decrypt cap: videos get a higher cap than other encrypted assets.
  static int maxDecryptBytesForPath(String requestedPath) {
    final lower = requestedPath.toLowerCase();
    if ((lower.endsWith('.mp4') || lower.endsWith('.webm')) &&
        lower.startsWith('resources/animations/')) {
      return maxPerAnimationVideoDecryptBytes;
    }
    if (lower.endsWith('.mp4') || lower.endsWith('.webm')) {
      return maxPerVideoDecryptBytes;
    }
    return maxPerFileDecryptBytes;
  }

  /// Returns the content key for a book (cache this for the reading session).
  static Future<Uint8List> getContentKey({
    required String bookId,
    required String keyEncB64,
    required String keyNonceB64,
  }) async {
    return _decryptContentKey(
      keyEncB64: keyEncB64,
      keyNonceB64: keyNonceB64,
      bookId: bookId,
    );
  }

  /// Decrypts a single file's bytes (e.g. chapter or asset). Use with [getContentKey].
  /// [aad] optional additional authenticated data (e.g. file path as UTF-8). Try empty then path if MAC fails.
  /// Throws if [encryptedBytes] exceed [maxPerFileDecryptBytes].
  static Future<Uint8List> decryptFileBytes({
    required Uint8List encryptedBytes,
    required Uint8List contentKey,
    String? requestedPath,
    List<int>? aad,
  }) async {
    final maxAllowed = requestedPath == null
        ? maxPerFileDecryptBytes
        : maxDecryptBytesForPath(requestedPath);
    if (encryptedBytes.length > maxAllowed) {
      throw Exception(
        'File too large to decrypt (${(encryptedBytes.length / (1024 * 1024)).toStringAsFixed(1)} MB). Max: ${(maxAllowed / (1024 * 1024)).toStringAsFixed(1)} MB.',
      );
    }
    final aadList = aad ?? [];
    try {
      return await _decryptFileContent(
        encryptedData: encryptedBytes,
        contentKey: contentKey,
        aad: aadList,
      );
    } catch (e) {
      _logDecrypt(
        'decryptFileBytes failed',
        requestedPath: requestedPath,
        dataLength: encryptedBytes.length,
        error: e,
      );
      rethrow;
    }
  }

  /// Call from reading screen / HTTP server when decrypt fails; logs path and error to decrypt_log.txt.
  static void logDecryptFailure({
    required String requestedPath,
    required int fileSizeBytes,
    required Object error,
  }) {
    _logDecrypt(
      'serve decrypt failed',
      requestedPath: requestedPath,
      dataLength: fileSizeBytes,
      error: error,
    );
  }

  /// Call from reading screen / HTTP server when file is intentionally blocked by size cap.
  static void logDecryptBlocked({
    required String requestedPath,
    required int fileSizeBytes,
    required int maxAllowedBytes,
  }) {
    _logDecrypt(
      'serve decrypt blocked (file too large)',
      requestedPath: requestedPath,
      dataLength: fileSizeBytes,
      error: 'max_allowed_bytes=$maxAllowedBytes',
    );
  }

  /// Generic timeline/event logging (for click/decrypt/range diagnostics).
  static void logServerEvent({
    required String message,
    String? requestedPath,
    int? sizeBytes,
    Object? details,
  }) {
    _logDecrypt(
      message,
      requestedPath: requestedPath,
      dataLength: sizeBytes,
      error: details,
    );
  }

  /// Tries decrypt with empty AAD first, then with [requestedPath] as AAD (UTF-8). Use for per-file AAD schemes.
  static Future<Uint8List> decryptFileBytesWithOptionalAad({
    required Uint8List encryptedBytes,
    required Uint8List contentKey,
    required String requestedPath,
  }) async {
    final normalized = requestedPath.replaceAll('\\', '/');
    final lower = normalized.toLowerCase();
    final withLeading = normalized.startsWith('/') ? normalized : '/$normalized';
    final lowerWithLeading = lower.startsWith('/') ? lower : '/$lower';

    Future<Uint8List> tryWith(List<int> aad) {
      return decryptFileBytes(
        encryptedBytes: encryptedBytes,
        contentKey: contentKey,
        requestedPath: requestedPath,
        aad: aad,
      );
    }

    try {
      return await tryWith([]);
    } catch (_) {
      // Try common AAD path variants used by different packers.
      try {
        return await tryWith(utf8.encode(normalized));
      } catch (_) {
        try {
          return await tryWith(utf8.encode(lower));
        } catch (_) {
          try {
            return await tryWith(utf8.encode(withLeading));
          } catch (_) {
            return await tryWith(utf8.encode(lowerWithLeading));
          }
        }
      }
    }
  }

  /// Logs decryption success to decrypt_log.txt (for pre-load check).
  static void logDecryptSuccess({String? path, int? size}) {
    _logDecrypt('decrypt OK', requestedPath: path, dataLength: size);
  }
}

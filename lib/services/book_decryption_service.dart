import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter/foundation.dart';
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
class BookDecryptionService {
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
    } catch (e, st) {
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
    } catch (e, st) {
      if (e is Exception) rethrow;
      throw Exception('Content key decryption failed: $e');
    }
  }

  static Future<Uint8List> _decryptFileContent({
    required Uint8List encryptedData,
    required Uint8List contentKey,
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
        aad: [],
      );
      return Uint8List.fromList(decrypted);
    } catch (e, st) {
      if (e is Exception) rethrow;
      throw Exception('File decryption failed: $e');
    }
  }
}

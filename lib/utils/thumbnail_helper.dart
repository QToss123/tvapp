import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// Downloads and caches book thumbnails locally for offline use.
class ThumbnailHelper {
  /// Downloads thumbnail from [url] and saves to [thumbnailsDir] with filename based on [id].
  /// Returns the local file path on success, null on failure.
  static Future<String?> downloadAndSave(
    String url, {
    required String thumbnailsDir,
    required String id,
  }) async {
    if (url.isEmpty || !url.startsWith('http')) return null;
    try {
      final dir = Directory(thumbnailsDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final ext = _extensionFromUrl(url);
      final fileName = '${_sanitizeId(id)}$ext';
      final filePath = path.join(thumbnailsDir, fileName);
      final file = File(filePath);

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Timeout');
        },
      );
      if (response.statusCode != 200) return null;

      await file.writeAsBytes(response.bodyBytes);
      return filePath;
    } catch (e) {
      return null;
    }
  }

  static String _extensionFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      final p = uri.path;
      if (p.endsWith('.png')) return '.png';
      if (p.endsWith('.gif')) return '.gif';
      if (p.endsWith('.webp')) return '.webp';
      if (p.endsWith('.jfif')) return '.jfif';
      if (p.endsWith('.jpeg')) return '.jpeg';
      if (p.endsWith('.jpg')) return '.jpg';
    }
    return '.jpg';
  }

  static String _sanitizeId(String id) {
    return id.replaceAll(RegExp(r'[^\w\-]'), '_');
  }
}

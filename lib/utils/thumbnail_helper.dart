import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// Downloads and caches book thumbnails locally for offline use.
class ThumbnailHelper {
  /// Downloads thumbnail from [url] and saves to [thumbnailsDir] with filename based on [id].
  /// Streams to file to avoid loading entire image in memory (OOM fix).
  /// Returns the local file path on success, null on failure.
  static Future<String?> downloadAndSave(
    String url, {
    required String thumbnailsDir,
    required String id,
    int maxSizeBytes = 5 * 1024 * 1024, // 5 MB limit for thumbnails
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

      final request = await http.Client()
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw Exception('Timeout');
            },
          );
      if (request.statusCode != 200) return null;

      final sink = file.openWrite();
      var totalBytes = 0;
      try {
        await for (final chunk in request.stream) {
          totalBytes += chunk.length;
          if (totalBytes > maxSizeBytes) {
            await sink.close();
            await file.delete();
            return null; // Abort if too large (avoid OOM)
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
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

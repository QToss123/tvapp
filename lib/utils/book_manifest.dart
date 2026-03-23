import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

/// Loads the set of encrypted file paths from a book's manifest.json.
/// Use this set to decide which requested paths should be decrypted on serve.
///
/// manifest.json may look like:
/// - { "encrypted_files": ["resources/book/page_1.webp", "resources/Animations/Page_13.mp4", ...] }
/// - { "encrypted": ["resources/1.webp", "resources/2.webp", ...] }
/// - { "encryptedFiles": ["path1", "path2", ...] }
/// - { "files": [ { "path": "resources/a.webp", "encrypted": true }, ... ] }
///
/// Returns null if manifest.json is missing or invalid; then callers fall back
/// to the default rule (e.g. paths under resources/ are encrypted).
/// Paths in the set are normalized (forward slashes, no leading slash, lowercase).
Future<Set<String>?> loadEncryptedPathsFromManifest(String bookDirPath) async {
  try {
    final manifestFile = File(path.join(bookDirPath, 'manifest.json'));
    if (!await manifestFile.exists()) return null;
    final content = await manifestFile.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>?;
    if (json == null) return null;

    final Set<String> out = {};

    // "encrypted_files": ["path1", "path2", ...] (e.g. book manifest from Liqvid)
    final encFilesList = json['encrypted_files'];
    if (encFilesList is List) {
      for (final e in encFilesList) {
        if (e is String) out.add(_normalizePath(e));
      }
    }

    // "encrypted": ["path1", "path2", ...]
    final encList = json['encrypted'];
    if (encList is List) {
      for (final e in encList) {
        if (e is String) out.add(_normalizePath(e));
      }
    }

    // "encryptedFiles": ["path1", ...]
    final encFiles = json['encryptedFiles'];
    if (encFiles is List) {
      for (final e in encFiles) {
        if (e is String) out.add(_normalizePath(e));
      }
    }

    // "files": [ { "path": "...", "encrypted": true }, ... ]
    final files = json['files'];
    if (files is List) {
      for (final item in files) {
        if (item is Map<String, dynamic> &&
            (item['encrypted'] == true || item['encrypted'] == 'true')) {
          final p = item['path'];
          if (p is String) out.add(_normalizePath(p));
        }
      }
    }

    return out.isEmpty ? null : out;
  } catch (_) {
    return null;
  }
}

String _normalizePath(String p) {
  return p
      .replaceAll(r'\', '/')
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'^/+'), '');
}

/// Returns true if [requestedPath] should be decrypted.
/// [encryptedPaths] from [loadEncryptedPathsFromManifest]; if null or empty,
/// falls back to treating paths under resources/ as encrypted.
bool isEncryptedPath(String requestedPath, Set<String>? encryptedPaths) {
  final normalized = requestedPath.replaceAll(r'\', '/').toLowerCase().trim();
  final noLeading = normalized.replaceFirst(RegExp(r'^/+'), '');
  // Product rule: everything under resources/ is encrypted.
  // Keep manifest matches too, so encrypted files outside resources/ still decrypt.
  if (noLeading.startsWith('resources/')) {
    return true;
  }
  if (encryptedPaths != null && encryptedPaths.isNotEmpty) {
    return encryptedPaths.contains(noLeading);
  }
  return false;
}

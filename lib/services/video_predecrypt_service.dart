import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'book_decryption_service.dart';

/// Params for background video pre-decryption.
class VideoPredecryptParams {
  final String bookDirPath;
  final String outputDirPath;
  final Uint8List contentKey;
  final List<String>? encryptedPathsLower;

  const VideoPredecryptParams({
    required this.bookDirPath,
    required this.outputDirPath,
    required this.contentKey,
    required this.encryptedPathsLower,
  });
}

/// Top-level for compute(): pre-decrypts encrypted video files in the book directory.
/// Returns number of files decrypted in this run.
Future<int> predecryptVideoFilesBackground(VideoPredecryptParams p) async {
  final bookDir = Directory(p.bookDirPath);
  if (!await bookDir.exists()) return 0;
  final outDir = Directory(p.outputDirPath);
  if (!await outDir.exists()) {
    await outDir.create(recursive: true);
  }

  final encryptedSet = p.encryptedPathsLower == null
      ? null
      : p.encryptedPathsLower!.map((e) => _normalizePath(e)).toSet();

  final candidates = <File>[];
  await for (final entity in bookDir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final rel = path.relative(entity.path, from: p.bookDirPath).replaceAll('\\', '/');
    final lower = rel.toLowerCase();
    final isVideo = lower.endsWith('.mp4') || lower.endsWith('.webm');
    if (!isVideo) continue;
    if (!_isEncryptedPath(rel, encryptedSet)) continue;
    candidates.add(entity);
  }

  // Prioritize animation videos so user taps are more likely to hit pre-decrypted cache.
  candidates.sort((a, b) {
    final ar = path.relative(a.path, from: p.bookDirPath).replaceAll('\\', '/').toLowerCase();
    final br = path.relative(b.path, from: p.bookDirPath).replaceAll('\\', '/').toLowerCase();
    final ap = ar.startsWith('resources/animations/') ? 0 : 1;
    final bp = br.startsWith('resources/animations/') ? 0 : 1;
    if (ap != bp) return ap - bp;
    return ar.compareTo(br);
  });

  int decryptedCount = 0;
  for (final entity in candidates) {
    if (entity is! File) continue;
    final rel = path.relative(entity.path, from: p.bookDirPath).replaceAll('\\', '/');
    final lower = rel.toLowerCase();
    final isVideo = lower.endsWith('.mp4') || lower.endsWith('.webm');
    if (!isVideo) continue;

    final outPath = path.join(p.outputDirPath, rel);
    final outFile = File(outPath);
    if (await outFile.exists()) continue; // already cached

    final encryptedBytes = await entity.readAsBytes();
    final maxAllowed = BookDecryptionService.maxDecryptBytesForPath(rel);
    if (encryptedBytes.length > maxAllowed) {
      continue;
    }

    final decrypted = await BookDecryptionService.decryptFileBytesWithOptionalAad(
      encryptedBytes: encryptedBytes,
      contentKey: p.contentKey,
      requestedPath: rel,
    );
    await outFile.parent.create(recursive: true);
    await outFile.writeAsBytes(decrypted, flush: false);
    decryptedCount++;
  }
  return decryptedCount;
}

bool _isEncryptedPath(String requestedPath, Set<String>? encryptedPathsLower) {
  final normalized = _normalizePath(requestedPath);
  if (encryptedPathsLower != null && encryptedPathsLower.isNotEmpty) {
    return encryptedPathsLower.contains(normalized);
  }
  return normalized.startsWith('resources/');
}

String _normalizePath(String p) {
  return p
      .replaceAll('\\', '/')
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'^/+'), '');
}


import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Utility class for handling ZIP file operations.
/// Uses InputFileStream + extractFileToDisk to avoid loading entire ZIP into memory (OOM fix).
class ZipHandler {
  /// Checks if a file is a ZIP file based on its extension
  static bool isZipFile(String filePath) {
    final lowerPath = filePath.toLowerCase();
    return lowerPath.endsWith('.zip');
  }

  /// Extracts a ZIP file to [extractDirPath] using streaming to avoid OOM on large files.
  static Future<String?> extractZipToDir(String zipFilePath, String extractDirPath) async {
    try {
      final zipFile = File(zipFilePath);
      if (!await zipFile.exists()) {
        throw Exception('ZIP file not found: $zipFilePath');
      }
      final extractDir = Directory(extractDirPath);
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create(recursive: true);

      // Use archive_io extractFileToDisk: streams from InputFileStream, avoids readAsBytes OOM
      await extractFileToDisk(zipFilePath, extractDirPath);

      return extractDir.path;
    } catch (e) {
      rethrow;
    }
  }

  /// Extracts a ZIP file to a temporary directory and returns the path to the extracted folder
  /// Also finds and returns the path to index.html if it exists
  static Future<String?> extractZipFile(String zipFilePath) async {
    final extractDir = await _getExtractDir(zipFilePath);
    return extractZipToDir(zipFilePath, extractDir.path);
  }

  /// Finds index.html in the extracted directory
  /// Returns the full path to index.html or null if not found
  static Future<String?> findIndexHtml(String directoryPath) async {
    try {
      final dir = Directory(directoryPath);
      if (!await dir.exists()) {
        return null;
      }

      // First, check if index.html is directly in the root
      final rootIndexHtml = File(path.join(directoryPath, 'index.html'));
      if (await rootIndexHtml.exists()) {
        return rootIndexHtml.path;
      }

      // Search recursively for index.html
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && path.basename(entity.path).toLowerCase() == 'index.html') {
          return entity.path;
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Same as [processBookFile] but runs extraction in background isolate to avoid ANR on TV.
  static Future<({String path, bool wasExtracted})> processBookFileOffMain(String filePath) async {
    if (!isZipFile(filePath)) {
      return (path: filePath, wasExtracted: false);
    }
    final extractDir = await _getExtractDir(filePath);
    if (await extractDir.exists()) {
      final existingIndex = await findIndexHtml(extractDir.path);
      if (existingIndex != null) {
        return (path: existingIndex, wasExtracted: false);
      }
    }
    final extractedPath = await compute(
      extractZipToDirBackground,
      (filePath, extractDir.path),
    );
    if (extractedPath == null) {
      throw Exception('Failed to extract ZIP file');
    }
    final indexHtmlPath = await findIndexHtml(extractedPath);
    if (indexHtmlPath != null) {
      return (path: indexHtmlPath, wasExtracted: true);
    }
    return (path: extractedPath, wasExtracted: true);
  }

  /// Checks if file is ZIP and extracts it if necessary
  /// Returns the path to the file/folder to load, and whether it was extracted
  static Future<({String path, bool wasExtracted})> processBookFile(String filePath) async {
    if (!isZipFile(filePath)) {
      // Not a ZIP file, return as is
      return (path: filePath, wasExtracted: false);
    }

    // Reuse previously extracted folder if it exists and has index.html
    final extractDir = await _getExtractDir(filePath);
    if (await extractDir.exists()) {
      final existingIndex = await findIndexHtml(extractDir.path);
      if (existingIndex != null) {
        return (path: existingIndex, wasExtracted: false);
      }
    }

    // It's a ZIP file, extract it
    final extractedPath = await extractZipFile(filePath);
    
    if (extractedPath == null) {
      throw Exception('Failed to extract ZIP file');
    }

    // Try to find index.html in the extracted directory
    final indexHtmlPath = await findIndexHtml(extractedPath);
    
    if (indexHtmlPath != null) {
      // Return the path to index.html
      return (path: indexHtmlPath, wasExtracted: true);
    } else {
      // No index.html found, return the directory path
      // The existing code will handle finding index.html
      return (path: extractedPath, wasExtracted: true);
    }
  }

  static Future<Directory> _getExtractDir(String zipFilePath) async {
    final tempDir = await getTemporaryDirectory();
    return Directory(
      path.join(
        tempDir.path,
        'extracted_books',
        path.basenameWithoutExtension(zipFilePath),
      ),
    );
  }

  /// Returns the extract directory path for a zip (for cleanup or unzip-first flow).
  static Future<String> getExtractDirPath(String zipFilePath) async {
    final dir = await _getExtractDir(zipFilePath);
    return dir.path;
  }
}

/// Top-level for compute(). Extracts zip to dir; returns extracted path or null.
Future<String?> extractZipToDirBackground((String zipPath, String extractDirPath) params) async {
  return ZipHandler.extractZipToDir(params.$1, params.$2);
}

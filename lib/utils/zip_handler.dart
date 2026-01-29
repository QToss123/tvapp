import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Utility class for handling ZIP file operations
class ZipHandler {
  /// Checks if a file is a ZIP file based on its extension
  static bool isZipFile(String filePath) {
    final lowerPath = filePath.toLowerCase();
    return lowerPath.endsWith('.zip');
  }

  /// Extracts a ZIP file to a temporary directory and returns the path to the extracted folder
  /// Also finds and returns the path to index.html if it exists
  static Future<String?> extractZipFile(String zipFilePath) async {
    try {
      debugPrint('Extracting ZIP file: $zipFilePath');
      
      final zipFile = File(zipFilePath);
      if (!await zipFile.exists()) {
        throw Exception('ZIP file not found: $zipFilePath');
      }

      // Read the ZIP file
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Get temporary directory for extraction
      final extractDir = await _getExtractDir(zipFilePath);
      
      // Create extraction directory if it doesn't exist
      if (await extractDir.exists()) {
        // Delete existing directory to avoid conflicts
        await extractDir.delete(recursive: true);
      }
      await extractDir.create(recursive: true);

      debugPrint('Extracting to: ${extractDir.path}');

      // Extract all files from the archive
      for (final file in archive) {
        final fileName = file.name;
        
        // Skip directories (they'll be created automatically)
        if (file.isFile) {
          final filePath = path.join(extractDir.path, fileName);
          final outputFile = File(filePath);
          
          // Create parent directories if they don't exist
          await outputFile.parent.create(recursive: true);
          
          // Write file content
          await outputFile.writeAsBytes(file.content as List<int>);
        }
      }

      debugPrint('Successfully extracted ZIP file to: ${extractDir.path}');
      return extractDir.path;
    } catch (e) {
      debugPrint('Error extracting ZIP file: $e');
      rethrow;
    }
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
        debugPrint('Found index.html at root: ${rootIndexHtml.path}');
        return rootIndexHtml.path;
      }

      // Search recursively for index.html
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && path.basename(entity.path).toLowerCase() == 'index.html') {
          debugPrint('Found index.html: ${entity.path}');
          return entity.path;
        }
      }

      debugPrint('index.html not found in extracted directory');
      return null;
    } catch (e) {
      debugPrint('Error searching for index.html: $e');
      return null;
    }
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
        debugPrint('Reusing existing extracted folder: ${extractDir.path}');
        return (path: existingIndex, wasExtracted: false);
      }
    }

    // It's a ZIP file, extract it
    debugPrint('File is a ZIP, extracting...');
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
}

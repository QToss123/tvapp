import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:path/path.dart' as path;
import 'api_service.dart';
import 'database_service.dart';
import '../models/book.dart';
import '../utils/thumbnail_helper.dart';

const _taskName = 'book_sync_task';
const _prefCourses = 'background_sync_courses';
const _prefStorage = 'storageLocation';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != _taskName) return false;
    try {
      await _runBackgroundSync();
      return true;
    } catch (e, st) {
      debugPrint('[BackgroundSync] Task failed: $e\n$st');
      return false;
    }
  });
}

Future<void> _runBackgroundSync() async {
  final prefs = await SharedPreferences.getInstance();
  final storageLocation = prefs.getString(_prefStorage);
  final coursesJson = prefs.getString(_prefCourses);

  if (storageLocation == null ||
      storageLocation.isEmpty ||
      storageLocation == 'Not selected' ||
      coursesJson == null ||
      coursesJson.isEmpty) {
    return;
  }

  final list = jsonDecode(coursesJson) as List<dynamic>;
  final allCourses = list.cast<Map<String, dynamic>>();

  for (final course in allCourses) {
    final courseId = course['id'] as int? ?? 0;
    try {
      final title = course['title']?.toString() ?? 'Untitled';
      final productName = course['product_name']?.toString() ?? 'Unknown Product';

      // Skip if already downloaded
      final existingPath = await DatabaseService.getFilePathByCourseId(courseId);
      if (existingPath != null && existingPath.isNotEmpty) {
        if (await File(existingPath).exists()) {
          continue;
        }
      }

      final downloadResult = await ApiService.downloadCourse(
        courseId,
        targetDirectory: storageLocation,
        onProgress: null,
        checkExisting: (encId) => DatabaseService.getFilePathByEncBookId(encId),
      );

      if (downloadResult['success'] != true) continue;

      final filePath = downloadResult['filePath'] as String;
      // Save ZIP path only; extraction happens when user opens the book
      final finalPath = filePath;
      final encBookId = downloadResult['encBookId'] as String?;
      final encBookPath = downloadResult['encBookPath'] as String?;
      final encKeyB64 = downloadResult['encKeyB64'] as String?;
      final encNonceB64 = downloadResult['encNonceB64'] as String?;

      final thumb = course['thumbnail']?.toString() ??
          course['product_thumbnail']?.toString();
      String? thumbnailLocalPath;
      if (thumb != null && thumb.isNotEmpty && thumb.startsWith('http')) {
        final thumbnailsDir = path.join(storageLocation, 'thumbnails');
        thumbnailLocalPath = await ThumbnailHelper.downloadAndSave(
          thumb,
          thumbnailsDir: thumbnailsDir,
          id: encBookId ?? 'course_$courseId',
        );
      }
      final book = Book(
        title: title,
        author: productName,
        progress: 0,
        thumbnail: thumb,
        thumbnailLocalPath: thumbnailLocalPath,
        contentUrl: finalPath.startsWith('/')
            ? 'file://$finalPath'
            : finalPath.startsWith('file://')
                ? finalPath
                : 'file:///$finalPath',
        encBookId: encBookId,
        encBookPath: encBookPath,
        encKeyB64: encKeyB64,
        encNonceB64: encNonceB64,
      );

      await DatabaseService.insertBook(
        book,
        courseId: courseId,
        filePath: finalPath,
      );
    } catch (e, st) {
      debugPrint('[BackgroundSync] Course $courseId failed: $e\n$st');
    }
  }

  await prefs.remove(_prefCourses);
  await prefs.setBool('syncCompleted', true);
}

Future<void> enqueueBackgroundSync(List<Map<String, dynamic>> courses) async {
  if (!Platform.isAndroid) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefCourses, jsonEncode(courses));
  await Workmanager().registerOneOffTask(
    _taskName,
    _taskName,
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );
}

Future<void> initWorkManager() async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(callbackDispatcher);
}

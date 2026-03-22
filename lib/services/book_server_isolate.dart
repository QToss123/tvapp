import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import '../utils/book_manifest.dart';
import 'book_decryption_service.dart';

/// Parameters sent from main isolate to server isolate: [bookDirPath, contentKey, port].
/// contentKey can be null (no encryption).
const int _paramBookDirPath = 0;
const int _paramContentKey = 1;
const int _paramPort = 2;

/// Entry point for the server isolate. Receives main's SendPort, then receives [bookDirPath, contentKey?, port].
/// Sends 'ready' when server is listening, then listens for 'close' to shut down.
void bookServerIsolateEntry(SendPort mainSendPort) async {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  HttpServer? server;
  receivePort.listen((message) async {
    if (message is List && server == null) {
      final bookDirPath = message[_paramBookDirPath] as String;
      final contentKey = message[_paramContentKey] as Uint8List?;
      final port = message[_paramPort] as int;
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
        final encryptedPaths = await loadEncryptedPathsFromManifest(bookDirPath);
        mainSendPort.send('ready');
        _handleRequests(server!, bookDirPath, contentKey, encryptedPaths);
      } catch (e) {
        mainSendPort.send(['error', e.toString()]);
      }
    } else if (message == 'close') {
      try {
        await server?.close(force: true);
      } catch (_) {}
      receivePort.close();
    }
  });
}

void _handleRequests(HttpServer server, String bookDirPath, Uint8List? contentKey, Set<String>? encryptedPaths) {
  final bookDirectory = Directory(bookDirPath);
  String? cachedDecryptedPath;
  Uint8List? cachedDecryptedBytes;
  final Set<String> first206VideoLogged = <String>{};
  server.listen((HttpRequest request) async {
    try {
      var requestedPath = request.uri.path;
      if (requestedPath.startsWith('/')) requestedPath = requestedPath.substring(1);
      requestedPath = Uri.decodeComponent(requestedPath);
      if (requestedPath.contains('..')) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.set('Content-Type', 'text/plain; charset=utf-8')
          ..write('Invalid path')
          ..close();
        return;
      }
      if (requestedPath.isEmpty || requestedPath == '/') requestedPath = 'index.html';

      var filePath = path.join(bookDirPath, requestedPath);
      var file = File(filePath);
      if (!await file.exists()) {
        final resolved = await _resolvePathCaseInsensitive(bookDirectory, requestedPath);
        if (resolved != null) {
          filePath = resolved;
          file = File(filePath);
        }
      }
      if (!await file.exists()) {
        final fallback = await _resolveChapterPathFallback(bookDirectory, requestedPath);
        if (fallback != null) {
          filePath = fallback;
          file = File(filePath);
        }
      }

      if (!await file.exists()) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..headers.set('Content-Type', 'text/plain; charset=utf-8')
          ..write('File not found: ${request.uri.path}')
          ..close();
        return;
      }

      final ext = path.extension(filePath).toLowerCase();
      final extFromRequest = ext.isEmpty && requestedPath.contains('.')
          ? '.${requestedPath.split('.').last.toLowerCase()}'
          : ext;
      final mimeStr = _mimeTypeForExtension(extFromRequest.isEmpty ? ext : extFromRequest);
      final pathForDecrypt = path.relative(filePath, from: bookDirPath).replaceAll('\\', '/');
      final predecryptedPath = _predecryptedVideoPath(bookDirPath, pathForDecrypt);
      var servedFromPredecrypted = false;
      if (_isVideoPath(pathForDecrypt)) {
        final pre = File(predecryptedPath);
        if (await pre.exists()) {
          file = pre;
          filePath = predecryptedPath;
          servedFromPredecrypted = true;
        }
      }
      final isEncrypted = contentKey != null &&
          !servedFromPredecrypted &&
          isEncryptedPath(pathForDecrypt, encryptedPaths);
      final fileLength = await file.length();

      final maxAllowed = BookDecryptionService.maxDecryptBytesForPath(pathForDecrypt);
      if (isEncrypted && fileLength > maxAllowed) {
        BookDecryptionService.logDecryptBlocked(
          requestedPath: pathForDecrypt,
          fileSizeBytes: fileLength,
          maxAllowedBytes: maxAllowed,
        );
        request.response
          ..statusCode = 413
          ..headers.set('Content-Type', 'text/plain; charset=utf-8')
          ..write('File too large to decrypt on this device.')
          ..close();
        return;
      }

      final range = _parseByteRange(request.headers.value(HttpHeaders.rangeHeader), fileLength);
      if (isEncrypted) {
        if (_isVideoPath(pathForDecrypt)) {
          final cachedVideoFile = File(_predecryptedVideoPath(bookDirPath, pathForDecrypt));
          if (!await cachedVideoFile.exists()) {
            BookDecryptionService.logServerEvent(
              message: 'video decrypt start',
              requestedPath: pathForDecrypt,
            );
            final encryptedBytes = await file.readAsBytes();
            Uint8List decryptedVideoBytes;
            try {
              decryptedVideoBytes = await BookDecryptionService.decryptFileBytesWithOptionalAad(
                encryptedBytes: encryptedBytes,
                contentKey: contentKey!,
                requestedPath: pathForDecrypt,
              );
            } catch (e) {
              final isMacError = e.toString().toLowerCase().contains('mac') ||
                  e.toString().toLowerCase().contains('secretboxauthentication');
              if (!isMacError) {
                request.response
                  ..statusCode = HttpStatus.internalServerError
                  ..headers.set('Content-Type', 'text/plain; charset=utf-8')
                  ..write('Decryption failed: $e')
                  ..close();
                return;
              }
              decryptedVideoBytes = encryptedBytes;
            }
            await cachedVideoFile.parent.create(recursive: true);
            await cachedVideoFile.writeAsBytes(decryptedVideoBytes, flush: false);
            BookDecryptionService.logServerEvent(
              message: 'video decrypt end',
              requestedPath: pathForDecrypt,
              sizeBytes: decryptedVideoBytes.length,
            );
          }

          final cachedLength = await cachedVideoFile.length();
          final videoRange = _parseByteRange(
            request.headers.value(HttpHeaders.rangeHeader),
            cachedLength,
          );
          final response = request.response;
          response
            ..headers.set('Content-Type', mimeStr)
            ..headers.contentType = ContentType.parse(mimeStr)
            ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
          if (videoRange != null) {
            final start = videoRange.start;
            final end = videoRange.end;
            if (!first206VideoLogged.contains(pathForDecrypt)) {
              first206VideoLogged.add(pathForDecrypt);
              BookDecryptionService.logServerEvent(
                message: 'video first 206 response sent',
                requestedPath: pathForDecrypt,
                details: 'range=$start-$end',
              );
            }
            response
              ..statusCode = HttpStatus.partialContent
              ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$cachedLength')
              ..headers.contentLength = end - start + 1;
            await for (final chunk in cachedVideoFile.openRead(start, end + 1)) {
              response.add(chunk);
            }
            await response.close();
          } else {
            response.headers.contentLength = cachedLength;
            await for (final chunk in cachedVideoFile.openRead()) {
              response.add(chunk);
            }
            await response.close();
          }
          return;
        }

        Uint8List? toServe;
        if (cachedDecryptedPath == pathForDecrypt && cachedDecryptedBytes != null) {
          toServe = cachedDecryptedBytes!;
        } else {
          final encryptedBytes = await file.readAsBytes();
          try {
            toServe = await BookDecryptionService.decryptFileBytesWithOptionalAad(
              encryptedBytes: encryptedBytes,
              contentKey: contentKey!,
              requestedPath: pathForDecrypt,
            );
            // Cache decrypted bytes for repeated range requests (especially mp4 playback).
            final shouldCache = pathForDecrypt.toLowerCase().endsWith('.mp4') ||
                pathForDecrypt.toLowerCase().endsWith('.webm') ||
                pathForDecrypt.toLowerCase().endsWith('.css') ||
                pathForDecrypt.toLowerCase().endsWith('.js') ||
                pathForDecrypt.toLowerCase().endsWith('.html');
            if (shouldCache && toServe.length <= 8 * 1024 * 1024) {
              cachedDecryptedPath = pathForDecrypt;
              cachedDecryptedBytes = toServe;
            }
          } catch (e) {
            final isMacError = e.toString().toLowerCase().contains('mac') ||
                e.toString().toLowerCase().contains('secretboxauthentication');
            if (!isMacError) {
              request.response
                ..statusCode = HttpStatus.internalServerError
                ..headers.set('Content-Type', 'text/plain; charset=utf-8')
                ..write('Decryption failed: $e')
                ..close();
              return;
            }
            toServe = encryptedBytes;
          }
        }
        final response = request.response;
        response
          ..headers.set('Content-Type', mimeStr)
          ..headers.contentType = ContentType.parse(mimeStr)
          ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        final contentLength = toServe.length;
        final decryptedRange = _parseByteRange(
          request.headers.value(HttpHeaders.rangeHeader),
          contentLength,
        );
        if (decryptedRange != null) {
          final start = decryptedRange.start;
          final end = decryptedRange.end;
          final partial = toServe.sublist(start, end + 1);
          response
            ..statusCode = HttpStatus.partialContent
            ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$contentLength')
            ..headers.contentLength = partial.length
            ..add(partial)
            ..close();
        } else {
          response
            ..headers.contentLength = contentLength
            ..add(toServe)
            ..close();
        }
      } else {
        final response = request.response;
        response
          ..headers.set('Content-Type', mimeStr)
          ..headers.contentType = ContentType.parse(mimeStr)
          ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        if (range != null) {
          final start = range.start;
          final end = range.end;
          response
            ..statusCode = HttpStatus.partialContent
            ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$fileLength')
            ..headers.contentLength = end - start + 1;
          await for (final chunk in file.openRead(start, end + 1)) {
            response.add(chunk);
          }
          await response.close();
        } else {
          response.headers.contentLength = fileLength;
          await for (final chunk in file.openRead()) {
            response.add(chunk);
          }
          await response.close();
        }
      }
    } catch (e) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.set('Content-Type', 'text/plain; charset=utf-8')
        ..write('Server error: $e')
        ..close();
    }
  });
}

({int start, int end})? _parseByteRange(String? header, int totalLength) {
  if (header == null || !header.startsWith('bytes=')) return null;
  final value = header.substring(6).trim();
  if (value.isEmpty || value.contains(',')) return null;
  final parts = value.split('-');
  if (parts.length != 2) return null;
  final startStr = parts[0].trim();
  final endStr = parts[1].trim();
  if (startStr.isEmpty) {
    final suffix = int.tryParse(endStr);
    if (suffix == null || suffix <= 0) return null;
    final start = (totalLength - suffix).clamp(0, totalLength - 1);
    return (start: start, end: totalLength - 1);
  }
  final start = int.tryParse(startStr);
  if (start == null || start < 0 || start >= totalLength) return null;
  final end = endStr.isEmpty ? totalLength - 1 : (int.tryParse(endStr) ?? totalLength - 1);
  if (end < start) return null;
  final normalizedEnd = end >= totalLength ? totalLength - 1 : end;
  return (start: start, end: normalizedEnd);
}

bool _isVideoPath(String relativePath) {
  final lower = relativePath.toLowerCase();
  return lower.endsWith('.mp4') || lower.endsWith('.webm');
}

String _predecryptedVideoPath(String bookDirPath, String relativePath) {
  return path.join(bookDirPath, '.decrypted_video_cache', relativePath);
}

String _mimeTypeForExtension(String ext) {
  switch (ext) {
    case '.html':
    case '.htm':
      return 'text/html; charset=utf-8';
    case '.css':
      return 'text/css; charset=utf-8';
    case '.js':
      return 'application/javascript; charset=utf-8';
    case '.json':
      return 'application/json; charset=utf-8';
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.gif':
      return 'image/gif';
    case '.svg':
      return 'image/svg+xml';
    case '.webp':
      return 'image/webp';
    case '.mp3':
      return 'audio/mpeg';
    case '.mp4':
      return 'video/mp4';
    case '.wav':
      return 'audio/wav';
    case '.woff':
      return 'font/woff';
    case '.woff2':
      return 'font/woff2';
    case '.ttf':
      return 'font/ttf';
    case '.xml':
      return 'application/xml; charset=utf-8';
    default:
      return 'application/octet-stream';
  }
}

Future<String?> _resolvePathCaseInsensitive(Directory dir, String relativePath) async {
  final parts = relativePath.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return null;
  String currentPath = dir.path;
  for (int i = 0; i < parts.length; i++) {
    final name = parts[i];
    final direct = File(path.join(currentPath, name));
    if (await direct.exists()) {
      currentPath = direct.path;
      continue;
    }
    String? found;
    await for (final entity in Directory(currentPath).list(followLinks: false)) {
      if (path.basename(entity.path).toLowerCase() == name.toLowerCase()) {
        found = entity.path;
        break;
      }
    }
    if (found == null) return null;
    currentPath = found;
  }
  return currentPath;
}

Future<String?> _resolveChapterPathFallback(Directory bookDirectory, String requestedPath) async {
  final fileName = path.basename(requestedPath);
  if (fileName.isEmpty) return null;
  final alternates = <String>[
    requestedPath.replaceFirst('page/', 'pages/'),
    requestedPath.replaceFirst('pages/', 'page/'),
    requestedPath.replaceFirst('page/', 'chapters/'),
    requestedPath.replaceFirst('chapters/', 'page/'),
    requestedPath.replaceFirst('chapters/', 'pages/'),
    'pages/$fileName',
    'page/$fileName',
    'chapters/$fileName',
    fileName,
  ];
  for (final alt in alternates) {
    final full = path.join(bookDirectory.path, alt);
    final f = File(full);
    if (await f.exists()) return full;
  }
  try {
    await for (final entity in bookDirectory.list(recursive: true)) {
      if (entity is File && path.basename(entity.path).toLowerCase() == fileName.toLowerCase()) {
        return entity.path;
      }
    }
  } catch (_) {}
  return null;
}

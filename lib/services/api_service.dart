import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:tv_app_books/models/book_download_response.dart';
import 'package:tv_app_books/utils/device_id_helper.dart';

/// API Service for handling license validation and other API calls
class ApiService {
  static const String _backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://licenses.dbk.burlingtonenglish.in/',
  );
  static String get baseUrl =>
      '${_backendUrl.endsWith('/') ? _backendUrl.substring(0, _backendUrl.length - 1) : _backendUrl}/api/v1';
  static String get validateLicenseEndpoint => '$baseUrl/license/validate';
  static String get activateLicenseEndpoint => '$baseUrl/license/activate';
  static String get productListEndpoint => '$baseUrl/product/list';
  static String courseDownloadEndpoint(int courseId) => '$baseUrl/courses/$courseId/download';
  
  static const String _kDeviceIdPrefsKey = 'device_id';
  /// Returns a stable device ID from the device. Android: IMEI or androidId.
  /// Windows/Linux: deviceId/machineId + MAC. Stored in SharedPreferences and reused.
  static Future<String> getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_kDeviceIdPrefsKey);
      if (id == null || id.isEmpty) {
        id = await DeviceIdHelper.getPlatformDeviceId();
        // If platform returned a fallback (timestamp-based, changes every run), use persistent UUID
        if (id.startsWith('fallback_')) {
          id = 'dev_${const Uuid().v4()}';
        }
        await prefs.setString(_kDeviceIdPrefsKey, id);
      }
      return id;
    } catch (e) {
      return 'error-device-id';
    }
  }

  /// Validates license with the server
  /// Returns a map with validation result and expiry date
  static Future<Map<String, dynamic>> validateLicense(String licenseValue) async {
    try {
      final deviceId = await getDeviceId();
      final requestBody = {
        'license_value': licenseValue,
        'device_id': deviceId,
      };

      final response = await http.post(
        Uri.parse(validateLicenseEndpoint),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      await _logApiCall(
        method: 'POST',
        url: validateLicenseEndpoint,
        requestBody: requestBody,
        statusCode: response.statusCode,
        responseBody: response.body,
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        // Extract token from nested data structure
        String? token;
        String? expiryDate;
        
        if (responseData['data'] != null) {
          final data = responseData['data'];
          token = data['license_token'] ?? data['token'] ?? data['access_token'];
          expiryDate = data['expiry_date'] ?? data['expiryDate'];
        }

        if (token == null) {
          token = responseData['token'] ?? responseData['access_token'] ?? responseData['accessToken'] ?? responseData['license_token'];
        }
        expiryDate ??= responseData['expiry_date'] ?? responseData['expiryDate'];

        return {
          'success': true,
          'valid': responseData['valid'] ?? false,
          'expiryDate': expiryDate,
          'token': token,
          'message': responseData['message'] ?? 'License validated successfully',
        };
      } else {
        // Handle error responses - graceful messages for license deleted/not found
        try {
          final errorData = jsonDecode(response.body);
          var msg = errorData['message'] ?? errorData['error'] ?? 'License validation failed';
          if (response.statusCode == 401 || response.statusCode == 404) {
            final lower = msg.toString().toLowerCase();
            if (lower.contains('deleted') || lower.contains('not found') || lower.contains('invalid')) {
              msg = 'License key not found or has been deleted. Please contact support.';
            }
          }
          return {
            'success': false,
            'valid': false,
            'message': msg,
          };
        } catch (e) {
          return {
            'success': false,
            'valid': false,
            'message': 'Server error: ${response.statusCode}',
          };
        }
      }
    } catch (e) {
      await _logApiCall(
        method: 'POST',
        url: validateLicenseEndpoint,
        requestBody: {'license_value': licenseValue},
        error: e,
      );
      return {
        'success': false,
        'valid': false,
        'message': 'Network error: $e',
      };
    }
  }

  /// Activates license with the server using a Bearer token
  /// Returns a map with activation result and expiry date
  static Future<Map<String, dynamic>> activateLicense(
    String licenseValue,
    String token,
  ) async {
    try {
      final deviceId = await getDeviceId();
      final requestBody = {
        'license_value': licenseValue,
        'device_id': deviceId,
      };

      final response = await http.put(
        Uri.parse(activateLicenseEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      );

      await _logApiCall(
        method: 'PUT',
        url: activateLicenseEndpoint,
        requestBody: requestBody,
        statusCode: response.statusCode,
        responseBody: response.body,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'activated': data['activated'] ?? true,
          'expiryDate': data['expiry_date'] ?? data['expiryDate'],
          'message': data['message'] ?? 'License activated successfully',
        };
      } else {
        // Handle error responses
        try {
          final errorData = jsonDecode(response.body);
          return {
            'success': false,
            'activated': false,
            'message': errorData['message'] ?? errorData['error'] ?? 'License activation failed',
          };
        } catch (e) {
          return {
            'success': false,
            'activated': false,
            'message': 'Server error: ${response.statusCode}',
          };
        }
      }
    } catch (e) {
      await _logApiCall(
        method: 'PUT',
        url: activateLicenseEndpoint,
        requestBody: {'license_value': licenseValue},
        error: e,
      );
      return {
        'success': false,
        'activated': false,
        'message': 'Network error: $e',
      };
    }
  }

  /// Gets the stored license token from SharedPreferences
  static Future<String?> getStoredToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('license_token');
    } catch (e) {
      return null;
    }
  }

  /// Gets the stored license value from SharedPreferences
  static Future<String?> getStoredLicenseValue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('licenseNumber');
    } catch (e) {
      return null;
    }
  }

  /// Fetches the list of products/books from the server
  /// Returns a map with success status and list of products
  static Future<Map<String, dynamic>> getProductList() async {
    try {
      final token = await getStoredToken();

      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'message': 'License key not found or has been deleted. Please activate license in Settings.',
          'products': <Map<String, dynamic>>[],
        };
      }

      final licenseValue = await getStoredLicenseValue();
      if (licenseValue == null || licenseValue.trim().isEmpty) {
        return {
          'success': false,
          'message': 'License key not found or has been deleted. Please activate license in Settings.',
          'products': <Map<String, dynamic>>[],
        };
      }

      // Use GET request with body as shown in the curl command
      final request = http.Request(
        'GET',
        Uri.parse(productListEndpoint),
      );

      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      await _logApiCall(
        method: 'GET',
        url: productListEndpoint,
        statusCode: response.statusCode,
        responseBody: response.body,
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        // Handle different possible response formats
        List<Map<String, dynamic>> products = [];
        
        if (responseData is Map) {
          // Check for products array
          if (responseData['products'] != null && responseData['products'] is List) {
            products = List<Map<String, dynamic>>.from(responseData['products']);
          } else if (responseData['data'] != null) {
            final data = responseData['data'];
            if (data is List) {
              products = List<Map<String, dynamic>>.from(data);
            } else if (data is Map && data['products'] != null && data['products'] is List) {
              products = List<Map<String, dynamic>>.from(data['products']);
            }
          }
        } else if (responseData is List) {
          products = List<Map<String, dynamic>>.from(responseData);
        }

        // Also return the full response data for nested structure
        Map<String, dynamic>? responseDataObj;
        if (responseData is Map) {
          responseDataObj = Map<String, dynamic>.from(responseData);
        }

        return {
          'success': true,
          'products': products,
          'responseData': responseDataObj, // Include full response for nested structure
          'message': 'Products fetched successfully',
        };
      } else {
        // Handle error responses - graceful message for license deleted
        try {
          final errorData = jsonDecode(response.body);
          var msg = errorData['message'] ?? errorData['error'] ?? 'Failed to fetch products';
          if (response.statusCode == 401 || response.statusCode == 404) {
            final lower = msg.toString().toLowerCase();
            if (lower.contains('deleted') || lower.contains('not found') || lower.contains('invalid license')) {
              msg = 'License key not found or has been deleted. Please contact support.';
            }
          }
          return {
            'success': false,
            'message': msg,
            'products': <Map<String, dynamic>>[],
          };
        } catch (e) {
          return {
            'success': false,
            'message': 'Server error: ${response.statusCode}',
            'products': <Map<String, dynamic>>[],
          };
        }
      }
    } catch (e) {
      await _logApiCall(
        method: 'GET',
        url: productListEndpoint,
        error: e,
      );
      return {
        'success': false,
        'message': 'Network error: $e',
        'products': <Map<String, dynamic>>[],
      };
    }
  }

  /// Downloads a course/book file from the server
  /// Returns a map with download result and file path
  /// [onProgress] callback receives progress percentage (0-100)
  /// [targetDirectory] optional target directory for downloads (defaults to app documents)
  /// [isCancelled] when returns true, download is aborted (for pause support)
  /// [checkExisting] if provided and returns a path for encBookId, skips download when file exists
  static Future<Map<String, dynamic>> downloadCourse(
    int courseId, {
    Function(int progress)? onProgress,
    String? targetDirectory,
    bool Function()? isCancelled,
    Future<String?> Function(String encBookId)? checkExisting,
  }) async {
    try {
      final token = await getStoredToken();

      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'message': 'No authorization token found. Please activate license first.',
          'filePath': null,
        };
      }

      final licenseValue = await getStoredLicenseValue();
      if (licenseValue == null || licenseValue.trim().isEmpty) {
        return {
          'success': false,
          'message': 'No license found. Please activate license in Settings first.',
          'filePath': null,
        };
      }

      // Use GET request without body; only Authorization header
      final request = http.Request(
        'GET',
        Uri.parse(courseDownloadEndpoint(courseId)),
      );

      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });

      final response = await http.Response.fromStream(await request.send());

      await _logApiCall(
        method: 'GET',
        url: courseDownloadEndpoint(courseId),
        statusCode: response.statusCode,
        responseBody: response.body,
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        final downloadResponse = BookDownloadResponse.fromJson(responseData);
        final downloadUrl = downloadResponse.downloadUrl;
        final fileKey = responseData['file_key'] as String?;
        final keys = downloadResponse.bookEncryptionKeys;

        if (downloadUrl.isEmpty) {
          return {
            'success': false,
            'message': 'No download URL received from server',
            'filePath': null,
          };
        }

        // Check if file already exists (by enc_book_id) before downloading
        if (keys != null && checkExisting != null) {
          final existingPath = await checkExisting(keys.bookId);
          if (existingPath != null && existingPath.isNotEmpty) {
            final existingFile = File(existingPath);
            if (await existingFile.exists()) {
              return {
                'success': true,
                'filePath': existingPath,
                'message': 'File already exists',
                'isEncrypted': true,
                'encBookId': keys.bookId,
                'encKeyB64': keys.keyEncB64,
                'encNonceB64': keys.keyNonceB64,
                'encBookPath': keys.encBookPath,
              };
            }
          }
        }

        // Use target directory if provided (external storage), otherwise use app documents
        String coursesDir;
        if (targetDirectory != null && targetDirectory.isNotEmpty) {
          coursesDir = path.join(targetDirectory, 'courses');
        } else {
          final Directory? appDocDir = await getExternalStorageDirectory();
          final String downloadDir = appDocDir?.path ??
              (await getApplicationDocumentsDirectory()).path;
          coursesDir = path.join(downloadDir, 'courses');
        }

        final Directory coursesDirectory = Directory(coursesDir);
        if (!await coursesDirectory.exists()) {
          await coursesDirectory.create(recursive: true);
        }

        // Use enc_book_path filename when available (e.g. book_xxx_encrypted.zip)
        String fileName;
        if (keys != null && keys.encBookPath.isNotEmpty) {
          fileName = path.basename(keys.encBookPath);
        } else {
          String extension = '.zip';
          if (fileKey != null && fileKey.contains('.')) {
            extension = path.extension(fileKey);
          } else if (downloadUrl.contains('.zip')) {
            extension = '.zip';
          } else if (downloadUrl.contains('.html')) {
            extension = '.html';
          }
          fileName = 'course_$courseId$extension';
        }
        final String filePath = path.join(coursesDir, fileName);
        final File file = File(filePath);

        // Skip download if file already exists at target path (e.g. from previous download)
        if (await file.exists()) {
          return {
            'success': true,
            'filePath': filePath,
            'message': 'File already exists',
            'isEncrypted': keys != null,
            'encBookId': keys?.bookId,
            'encKeyB64': keys?.keyEncB64,
            'encNonceB64': keys?.keyNonceB64,
            'encBookPath': keys?.encBookPath,
          };
        }

        // Download file directly (encrypted files remain encrypted)
        final downloadRequest = await http.Client().send(
            http.Request('GET', Uri.parse(downloadUrl)));
        final contentLength = downloadRequest.contentLength;
        int downloadedBytes = 0;
        final sink = file.openWrite();
        bool cancelled = false;
        await for (final chunk in downloadRequest.stream) {
          if (isCancelled?.call() == true) {
            cancelled = true;
            break;
          }
          sink.add(chunk);
          downloadedBytes += chunk.length;
          if (contentLength != null &&
              contentLength > 0 &&
              onProgress != null) {
            onProgress(((downloadedBytes / contentLength) * 100).round());
          }
        }
        await sink.close();
        if (cancelled) {
          if (await file.exists()) await file.delete();
          return {
            'success': false,
            'cancelled': true,
            'message': 'Download paused',
            'filePath': null,
          };
        }

        return {
          'success': true,
          'filePath': filePath,
          'message': 'Course downloaded successfully',
          'isEncrypted': keys != null,
          'encBookId': keys?.bookId,
          'encKeyB64': keys?.keyEncB64,
          'encNonceB64': keys?.keyNonceB64,
          'encBookPath': keys?.encBookPath,
        };
      } else {
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>?;
          final msg = errorData?['message'] ?? errorData?['error'] ?? 'Failed to download course';
          return {
            'success': false,
            'message': msg is String ? msg : 'Failed to download course',
            'filePath': null,
          };
        } catch (_) {
          return {
            'success': false,
            'message': 'Server error: ${response.statusCode}',
            'filePath': null,
          };
        }
      }
    } catch (e) {
      await _logApiCall(
        method: 'GET',
        url: courseDownloadEndpoint(courseId),
        error: e,
      );
      // User-friendly message when internet is lost or connection fails during download
      final String message = _isNetworkError(e)
          ? 'Internet disconnected. Check your connection and try again.'
          : 'Download failed. Please try again.';
      return {
        'success': false,
        'message': message,
        'filePath': null,
      };
    }
  }

  static bool _isNetworkError(Object e) {
    if (e is SocketException) return true;
    if (e is HttpException) return true;
    if (e is HandshakeException) return true;
    if (e is TimeoutException) return true;
    if (e is IOException) return true;
    final s = e.toString().toLowerCase();
    return s.contains('socket') ||
        s.contains('connection') ||
        s.contains('network') ||
        s.contains('timeout') ||
        s.contains('host') ||
        s.contains('failed host lookup');
  }

  /// Append API call details to a log file (log.txt) next to the running executable.
  /// NOTE: Disabled for final Windows build.
  static Future<void> _logApiCall({
    required String method,
    required String url,
    Map<String, dynamic>? requestBody,
    int? statusCode,
    String? responseBody,
    Object? error,
  }) async {
    final buffer = StringBuffer()
      ..writeln('[ApiService] $method $url');

    if (requestBody != null) {
      buffer.writeln('[ApiService] Request: ${jsonEncode(requestBody)}');
    }
    if (statusCode != null) {
      buffer.writeln('[ApiService] Status: $statusCode');
    }
    if (responseBody != null && responseBody.isNotEmpty) {
      buffer.writeln('[ApiService] Response: $responseBody');
    }
    if (error != null) {
      buffer.writeln('[ApiService] Error: $error');
    }

    debugPrint(buffer.toString());
  }
}

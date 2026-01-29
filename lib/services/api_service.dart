import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:tv_app_books/models/book_download_response.dart';

/// API Service for handling license validation and other API calls
class ApiService {
  static const String baseUrl = 'https://burlington-celp.adurox.com/api/v1';
  static const String validateLicenseEndpoint = '$baseUrl/license/validate';
  static const String activateLicenseEndpoint = '$baseUrl/license/activate';
  static const String productListEndpoint = '$baseUrl/product/list';
  static String courseDownloadEndpoint(int courseId) => '$baseUrl/courses/$courseId/download';
  
  static const String _kDeviceIdPrefsKey = 'device_id';
  static const String _forcedDeviceId = 'tv_1769437510714_3f65d0e1';

  /// Returns a stable device ID (dynamic). Generated once per app install,
  /// stored in SharedPreferences, and reused for license/API calls.
  static Future<String> getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Force device ID override when requested
      await prefs.setString(_kDeviceIdPrefsKey, _forcedDeviceId);
      debugPrint('📱 Device ID (forced): $_forcedDeviceId');
      return _forcedDeviceId;
      var id = prefs.getString(_kDeviceIdPrefsKey);
      if (id == null || id.isEmpty) {
        id = 'tv_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(0xFFFFFFFF).toRadixString(16)}';
        await prefs.setString(_kDeviceIdPrefsKey, id);
        debugPrint('📱 Device ID (generated): $id');
      } else {
        debugPrint('📱 Device ID (stored): $id');
      }
      return id;
    } catch (e) {
      debugPrint('Error getting device ID: $e');
      return 'error-device-id';
    }
  }

  /// Validates license with the server
  /// Returns a map with validation result and expiry date
  static Future<Map<String, dynamic>> validateLicense(String licenseValue) async {
    try {
      debugPrint('═══════════════════════════════════════');
      debugPrint('🔵 API CALL: validateLicense');
      debugPrint('═══════════════════════════════════════');
      
      final deviceId = await getDeviceId();
      debugPrint('Validating license: $licenseValue');
      debugPrint('Device ID (dynamic): $deviceId');
      debugPrint('Endpoint: $validateLicenseEndpoint');

      final response = await http.post(
        Uri.parse(validateLicenseEndpoint),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'license_value': licenseValue,
          'device_id': deviceId,
        }),
      );

      debugPrint('License validation response status: ${response.statusCode}');
      debugPrint('License validation response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        debugPrint('Parsed response data type: ${responseData.runtimeType}');
        debugPrint('Response data keys: ${responseData.keys}');
        
        // Extract token from nested data structure
        String? token;
        String? expiryDate;
        
        if (responseData['data'] != null) {
          final data = responseData['data'];
          debugPrint('Found data object, type: ${data.runtimeType}');
          debugPrint('Data keys: ${data.keys}');
          debugPrint('Checking for license_token in data...');
          
          token = data['license_token'] ?? data['token'] ?? data['access_token'];
          expiryDate = data['expiry_date'] ?? data['expiryDate'];
          
          if (token != null) {
            debugPrint('✅ Token found in data object: ${token.substring(0, 20)}...');
          } else {
            debugPrint('❌ Token not found in data object');
          }
        } else {
          debugPrint('No data object in response');
        }
        
        // Fallback to root level
        if (token == null) {
          debugPrint('Trying root level token extraction...');
          token = responseData['token'] ?? responseData['access_token'] ?? responseData['accessToken'] ?? responseData['license_token'];
          if (token != null) {
            debugPrint('✅ Token found at root level: ${token.substring(0, 20)}...');
          }
        }
        
        expiryDate ??= responseData['expiry_date'] ?? responseData['expiryDate'];
        
        debugPrint('Final extracted token: ${token != null ? (token.substring(0, 20) + '... (length: ${token.length})') : 'null'}');
        debugPrint('Final extracted expiry date: $expiryDate');
        
        return {
          'success': true,
          'valid': responseData['valid'] ?? false,
          'expiryDate': expiryDate,
          'token': token,
          'message': responseData['message'] ?? 'License validated successfully',
        };
      } else {
        // Handle error responses
        try {
          final errorData = jsonDecode(response.body);
          return {
            'success': false,
            'valid': false,
            'message': errorData['message'] ?? 'License validation failed',
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
      debugPrint('Error validating license: $e');
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
      debugPrint('═══════════════════════════════════════');
      debugPrint('🟢 API CALL: activateLicense');
      debugPrint('═══════════════════════════════════════');
      
      final deviceId = await getDeviceId();
      debugPrint('Activating license: $licenseValue');
      debugPrint('Device ID (dynamic): $deviceId');
      debugPrint('Using token: ${token.substring(0, 20)}...');
      debugPrint('Endpoint: $activateLicenseEndpoint');
      debugPrint('Authorization Header: Bearer ${token.substring(0, 20)}...');

      final response = await http.put(
        Uri.parse(activateLicenseEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'license_value': licenseValue,
          'device_id': deviceId,
        }),
      );

      debugPrint('License activation response status: ${response.statusCode}');
      debugPrint('License activation response body: ${response.body}');

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
      debugPrint('Error activating license: $e');
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
      debugPrint('Checking for token in SharedPreferences with key: license_token');
      
      // Check all keys to debug
      final allKeys = prefs.getKeys();
      debugPrint('All SharedPreferences keys: $allKeys');
      
      final token = prefs.getString('license_token');
      if (token == null || token.isEmpty) {
        debugPrint('❌ No token found in SharedPreferences with key "license_token"');
        debugPrint('Available keys containing "token" or "license": ${allKeys.where((k) => k.contains('token') || k.contains('license')).toList()}');
      } else {
        debugPrint('✅ Token retrieved successfully: ${token.substring(0, 20)}... (length: ${token.length})');
      }
      return token;
    } catch (e) {
      debugPrint('Error getting stored token: $e');
      return null;
    }
  }

  /// Gets the stored license value from SharedPreferences
  static Future<String?> getStoredLicenseValue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('licenseNumber');
    } catch (e) {
      debugPrint('Error getting stored license value: $e');
      return null;
    }
  }

  /// Fetches the list of products/books from the server
  /// Returns a map with success status and list of products
  static Future<Map<String, dynamic>> getProductList() async {
    try {
      debugPrint('═══════════════════════════════════════');
      debugPrint('🟡 API CALL: getProductList');
      debugPrint('═══════════════════════════════════════');
      
      final token = await getStoredToken();

      if (token == null || token.isEmpty) {
        debugPrint('❌ ERROR: No authorization token found');
        return {
          'success': false,
          'message': 'No authorization token found. Please activate license first.',
          'products': <Map<String, dynamic>>[],
        };
      }

      final licenseValue = await getStoredLicenseValue();
      if (licenseValue == null || licenseValue.trim().isEmpty) {
        debugPrint('❌ ERROR: No license value found');
        return {
          'success': false,
          'message': 'No license found. Please activate license in Settings first.',
          'products': <Map<String, dynamic>>[],
        };
      }

      final deviceId = await getDeviceId();
      debugPrint('Fetching product list...');
      debugPrint('Using token: ${token.substring(0, 20)}...');
      debugPrint('License value (dynamic): $licenseValue');
      debugPrint('Device ID (dynamic): $deviceId');
      debugPrint('Endpoint: $productListEndpoint');

      final requestBody = {
        'license_value': licenseValue,
        'device_id': deviceId,
      };
      
      debugPrint('Product list request body: ${jsonEncode(requestBody)}');
      debugPrint('Authorization Header: Bearer ${token.substring(0, 20)}...');

      // Use GET request with body as shown in the curl command
      final request = http.Request(
        'GET',
        Uri.parse(productListEndpoint),
      );

      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });

      request.body = jsonEncode(requestBody);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('Product list response status: ${response.statusCode}');
      debugPrint('Product list response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        debugPrint('Product list response data type: ${responseData.runtimeType}');
        debugPrint('Product list response keys: ${responseData is Map ? responseData.keys : 'not a map'}');
        
        // Handle different possible response formats
        List<Map<String, dynamic>> products = [];
        
        if (responseData is Map) {
          // Check for products array
          if (responseData['products'] != null) {
            if (responseData['products'] is List) {
              products = List<Map<String, dynamic>>.from(responseData['products']);
              debugPrint('Found products array with ${products.length} items');
            } else {
              debugPrint('products field exists but is not a List, type: ${responseData['products'].runtimeType}');
            }
          } 
          // Check for data object that might contain products
          else if (responseData['data'] != null) {
            final data = responseData['data'];
            debugPrint('Found data object, type: ${data.runtimeType}');
            
            if (data is List) {
              products = List<Map<String, dynamic>>.from(data);
              debugPrint('data is a List with ${products.length} items');
            } else if (data is Map) {
              // If data is a Map, check if it has a products field
              if (data['products'] != null && data['products'] is List) {
                products = List<Map<String, dynamic>>.from(data['products']);
                debugPrint('Found products in data object with ${products.length} items');
              } else {
                debugPrint('data is a Map but no products array found. Keys: ${data.keys}');
              }
            }
          }
        } else if (responseData is List) {
          products = List<Map<String, dynamic>>.from(responseData);
          debugPrint('Response is a direct List with ${products.length} items');
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
        // Handle error responses
        try {
          final errorData = jsonDecode(response.body);
          return {
            'success': false,
            'message': errorData['message'] ?? errorData['error'] ?? 'Failed to fetch products',
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
      debugPrint('Error fetching product list: $e');
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
  static Future<Map<String, dynamic>> downloadCourse(
    int courseId, {
    Function(int progress)? onProgress,
    String? targetDirectory,
  }) async {
    try {
      final token = await getStoredToken();

      if (token == null || token.isEmpty) {
        debugPrint('❌ Download failed: No authorization token. Activate license in Settings first.');
        return {
          'success': false,
          'message': 'No authorization token found. Please activate license first.',
          'filePath': null,
        };
      }

      final licenseValue = await getStoredLicenseValue();
      if (licenseValue == null || licenseValue.trim().isEmpty) {
        debugPrint('❌ Download failed: No license. Set license in Settings first.');
        return {
          'success': false,
          'message': 'No license found. Please activate license in Settings first.',
          'filePath': null,
        };
      }

      final deviceId = await getDeviceId();
      debugPrint('═══════════════════════════════════════');
      debugPrint('🟣 API CALL: downloadCourse');
      debugPrint('═══════════════════════════════════════');
      debugPrint('Downloading course ID: $courseId...');
      debugPrint('Using token: ${token.substring(0, 20)}...');
      debugPrint('License value (dynamic): $licenseValue');
      debugPrint('Device ID (dynamic): $deviceId');

      final requestBody = {
        'license_value': licenseValue,
        'device_id': deviceId,
      };
      
      debugPrint('Course download request body: ${jsonEncode(requestBody)}');
      debugPrint('Endpoint: ${courseDownloadEndpoint(courseId)}');

      // Print curl for manual testing
      final curlApi = "curl -X GET '${courseDownloadEndpoint(courseId)}' \\\n"
          "  -H 'Content-Type: application/json' \\\n"
          "  -H 'Authorization: Bearer $token' \\\n"
          "  -d '${jsonEncode(requestBody)}'";
      debugPrint('📎 CURL (get download URL):\n$curlApi');

      // Use GET request with body as shown in the curl command
      final request = http.Request(
        'GET',
        Uri.parse(courseDownloadEndpoint(courseId)),
      );

      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });
      
      debugPrint('Authorization Header: Bearer ${token.substring(0, 20)}...');

      request.body = jsonEncode(requestBody);

      final response = await http.Response.fromStream(await request.send());

      debugPrint('Course download response status: ${response.statusCode}');
      debugPrint('Course download response body: ${response.body}');

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

        debugPrint('Download URL received: ${downloadUrl.substring(0, downloadUrl.length > 50 ? 50 : downloadUrl.length)}...');
        if (keys != null) {
          debugPrint('🔐 Encrypted book: ${keys.bookId}');
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

        String extension = '.zip';
        if (fileKey != null && fileKey.contains('.')) {
          extension = path.extension(fileKey);
        } else if (downloadUrl.contains('.zip')) {
          extension = '.zip';
        } else if (downloadUrl.contains('.html')) {
          extension = '.html';
        }

        final String fileName = 'course_$courseId$extension';
        final String filePath = path.join(coursesDir, fileName);
        final File file = File(filePath);

        debugPrint('📎 CURL (download file): curl -o "$fileName" "$downloadUrl"');

        if (await file.exists()) {
          await file.delete();
        }

        // Download file directly (encrypted files remain encrypted)
        debugPrint('Downloading file from URL...');
        final downloadRequest = await http.Client().send(
            http.Request('GET', Uri.parse(downloadUrl)));
        final contentLength = downloadRequest.contentLength;
        int downloadedBytes = 0;
        final sink = file.openWrite();
        await for (final chunk in downloadRequest.stream) {
          sink.add(chunk);
          downloadedBytes += chunk.length;
          if (contentLength != null &&
              contentLength > 0 &&
              onProgress != null) {
            onProgress(((downloadedBytes / contentLength) * 100).round());
          }
        }
        await sink.close();

        debugPrint('Course downloaded successfully to: $filePath');
        debugPrint('File size: ${await file.length()} bytes');

        debugPrint('🔐 Enc keys from download API: bookId=${keys?.bookId} '
            'keyEncB64=${keys?.keyEncB64 != null ? '***' : 'null'} '
            'keyNonceB64=${keys?.keyNonceB64 != null ? '***' : 'null'}');
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
        debugPrint('❌ Download API error: status=${response.statusCode} body=${response.body}');
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
    } catch (e, st) {
      debugPrint('❌ Error downloading course: $e');
      debugPrint('$st');
      return {
        'success': false,
        'message': 'Network error: $e',
        'filePath': null,
      };
    }
  }
}

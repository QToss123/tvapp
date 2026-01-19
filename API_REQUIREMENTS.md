# API Requirements & Permissions Documentation

## Current Implementation Status

### ✅ Currently Implemented (Local Only)

1. **Local Storage API** (`shared_preferences`)
   - Stores license number, activation status, expiry date
   - Stores sync type and storage location
   - No external API calls

2. **File System Access** (`path_provider`, `file_picker`)
   - Folder picker for storage location selection
   - Reading books from local assets
   - Reading books from external storage (file:// paths)

3. **WebView API** (`webview_flutter`)
   - Displays book content (HTML)
   - Supports local assets, external files, and network URLs

---

## Required APIs & Permissions

### 1. Android Permissions (Required)

Add these to `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Storage Permissions -->
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" 
        android:maxSdkVersion="32" />
    
    <!-- For Android 13+ (API 33+) -->
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
    
    <!-- Network Permissions (if downloading books) -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    
    <!-- For accessing external storage on Android TV -->
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" 
        tools:ignore="ScopedStorage" />
    
    <application>
        <!-- ... existing code ... -->
    </application>
</manifest>
```

**Note:** For Android 11+ (API 30+), you may need to use Scoped Storage or request `MANAGE_EXTERNAL_STORAGE` permission.

---

### 2. Flutter Packages (Currently Used)

```yaml
dependencies:
  shared_preferences: ^2.2.3      # Local data storage
  webview_flutter: ^4.4.2        # Book content display
  path_provider: ^2.1.1           # File system paths
  file_picker: ^8.1.2             # Folder selection
```

---

### 3. Potential External APIs (Not Currently Implemented)

If you want to add server-side functionality, you'll need:

#### A. License Validation API

**Purpose:** Validate license with server instead of local validation

**Required Endpoints:**
```
POST /api/v1/license/validate
Request Body:
{
  "licenseNumber": "LIQVID1234567890",
  "deviceId": "unique-device-id"
}

Response:
{
  "valid": true,
  "expiryDate": "2025-12-31",
  "message": "License validated successfully"
}
```

**Flutter Package Needed:**
```yaml
dependencies:
  http: ^1.1.0  # For API calls
  # or
  dio: ^5.4.0   # Alternative HTTP client
```

**Implementation Example:**
```dart
import 'package:http/http.dart' as http;
import 'dart:convert';

Future<bool> validateLicenseWithServer(String licenseNumber) async {
  try {
    final response = await http.post(
      Uri.parse('https://your-api.com/api/v1/license/validate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'licenseNumber': licenseNumber,
        'deviceId': await _getDeviceId(),
      }),
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['valid'] == true;
    }
    return false;
  } catch (e) {
    return false;
  }
}
```

---

#### B. Book Download/Sync API

**Purpose:** Download books from server based on license

**Required Endpoints:**
```
GET /api/v1/books/list
Headers:
  Authorization: Bearer {license_token}

Response:
{
  "books": [
    {
      "id": "book1",
      "title": "Book Title",
      "author": "Author Name",
      "thumbnail": "https://...",
      "downloadUrl": "https://.../book1.zip",
      "size": 1024000
    }
  ]
}

GET /api/v1/books/{bookId}/download
Headers:
  Authorization: Bearer {license_token}

Response: Binary file (ZIP or direct HTML)
```

**Flutter Packages Needed:**
```yaml
dependencies:
  http: ^1.1.0
  path_provider: ^2.1.1
  archive: ^3.4.0  # For extracting ZIP files
  permission_handler: ^11.0.0  # For runtime permissions
```

---

#### C. Book Sync API (For "from external" sync type)

**Purpose:** Sync books from external source (USB/SD card) to server

**Required Endpoints:**
```
POST /api/v1/books/sync
Headers:
  Authorization: Bearer {license_token}
  
Request Body:
{
  "books": [
    {
      "path": "/storage/XXXX-XXXX/books/book1",
      "metadata": {...}
    }
  ]
}
```

---

### 4. Device Information API

**Purpose:** Get unique device ID for license binding

**Flutter Package:**
```yaml
dependencies:
  device_info_plus: ^9.1.0
```

**Implementation:**
```dart
import 'package:device_info_plus/device_info_plus.dart';

Future<String> getDeviceId() async {
  final deviceInfo = DeviceInfoPlugin();
  if (Platform.isAndroid) {
    final androidInfo = await deviceInfo.androidInfo;
    return androidInfo.id; // Android ID
  }
  return 'unknown';
}
```

---

### 5. Network State API

**Purpose:** Check internet connectivity before API calls

**Flutter Package:**
```yaml
dependencies:
  connectivity_plus: ^5.0.0
```

---

## Recommended API Architecture

### Option 1: Minimal (Current - Local Only)
- ✅ No external APIs needed
- ✅ Works offline
- ❌ No server-side license validation
- ❌ No book download from server

### Option 2: Hybrid (Recommended)
- ✅ Local license validation (fallback)
- ✅ Server-side license validation (primary)
- ✅ Book download from server
- ✅ Offline support for downloaded books

### Option 3: Full Cloud
- ✅ All data on server
- ✅ Real-time sync
- ❌ Requires constant internet
- ❌ More complex implementation

---

## Implementation Priority

### Phase 1: Essential Permissions (Required Now)
1. ✅ Add storage permissions to AndroidManifest.xml
2. ✅ Test folder picker on Android TV
3. ✅ Verify external storage access

### Phase 2: Basic API Integration (If Needed)
1. Add `http` or `dio` package
2. Implement license validation API
3. Add device ID collection
4. Add network connectivity check

### Phase 3: Advanced Features (Optional)
1. Book download API
2. Progress tracking API
3. Analytics API
4. Update/notification API

---

## Current API Status Summary

| Feature | Status | API/Package Used |
|---------|--------|------------------|
| License Storage | ✅ Implemented | `shared_preferences` |
| License Validation | ✅ Local Only | `shared_preferences` |
| Folder Picker | ✅ Implemented | `file_picker` |
| Book Reading | ✅ Implemented | `webview_flutter` |
| External Storage | ✅ Implemented | `path_provider`, `dart:io` |
| Server License Validation | ❌ Not Implemented | Needs `http` package |
| Book Download | ❌ Not Implemented | Needs API + `http` package |
| Device ID | ❌ Not Implemented | Needs `device_info_plus` |
| Network Check | ❌ Not Implemented | Needs `connectivity_plus` |

---

## Next Steps

1. **Add Android Permissions** (Required for folder picker to work)
2. **Test on Android TV** (Verify folder picker works)
3. **Decide on API Requirements:**
   - Do you need server-side license validation?
   - Do you need book download from server?
   - Do you need sync functionality?

4. **If APIs are needed:**
   - Set up backend API endpoints
   - Add `http` or `dio` package
   - Implement API service classes
   - Add error handling and retry logic

---

## Code Examples

### Adding Permissions to AndroidManifest.xml

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    
    <!-- Add permissions here -->
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" 
        android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.INTERNET" />
    
    <application>
        <!-- ... existing code ... -->
    </application>
</manifest>
```

### Example API Service Class (If Needed)

```dart
// lib/services/api_service.dart
import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiService {
  static const String baseUrl = 'https://your-api.com/api/v1';
  
  Future<bool> validateLicense(String licenseNumber) async {
    // Implementation
  }
  
  Future<List<Book>> getBooks(String token) async {
    // Implementation
  }
  
  Future<void> downloadBook(String bookId, String savePath) async {
    // Implementation
  }
}
```

---

**Note:** Currently, the app works completely offline with local storage. External APIs are only needed if you want server-side features like license validation, book downloads, or sync functionality.

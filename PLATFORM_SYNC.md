# Platform Sync: Android, Windows, Linux

This document verifies that Android, Windows, and Linux code paths are in sync and consistent.

## 1. Main Entry (main.dart)

| Feature | Android | Windows | Linux |
|---------|:-------:|:-------:|:-----:|
| sqflite FFI init | ❌ (uses native) | ✅ | ✅ |
| WebView platform | ❌ (uses default) | ✅ WindowsWebViewPlatform | ✅ WindowsWebViewPlatform |
| cryptography_flutter | ✅ if present | ✅ if present | ✅ if present |
| WorkManager | ✅ | ❌ | ❌ |
| Full screen | ✅ immersiveSticky | ✅ edgeToEdge | ✅ edgeToEdge |
| Device ID | ApiService.getDeviceId() | ApiService.getDeviceId() | ApiService.getDeviceId() |

**Note:** WindowsWebViewPlatform from webview_win_floating supports both Windows and Linux.

## 2. Device ID (device_id_helper.dart + MainActivity.kt)

| Platform | Source | Format |
|----------|--------|--------|
| **Android** | IMEI (API ≤28) or androidId | `android_imei_xxx` or `android_xxx` |
| **Windows** | deviceId + MAC (getmac) | `win_{deviceId}_{mac}` |
| **Linux** | machineId + MAC (/sys/class/net) | `linux_{machineId}_{mac}` |

- Android: MethodChannel in MainActivity.kt → DeviceIdHelper
- Windows/Linux: device_info_plus + Process/File for MAC
- All platforms: No fixed IDs, always from device

## 3. Database (database_service.dart)

| Platform | Implementation |
|----------|----------------|
| Android | Native sqflite (SQLite via Android) |
| Windows | sqflite_common_ffi (SQLite via FFI) |
| Linux | sqflite_common_ffi (SQLite via FFI) |

Initialized in main.dart before any database call.

## 4. File Paths (reading_screen.dart)

| Platform | Handling |
|----------|----------|
| Windows | `_fileUrlToPath`: Drive letters (C:\), path separators |
| Linux | Standard Unix paths |
| Android | Standard paths, file:// URLs |

## 5. Storage / File Browser (file_browser.dart)

| Platform | Storage roots |
|----------|---------------|
| Windows | A:\, B:\, ..., Z:\ (drive letters) |
| Linux | /, /home, /mnt, /media |
| Android | Internal + USB drives |

## 6. Permissions (settings_screen.dart, permission_helper.dart)

| Platform | Storage permission |
|----------|---------------------|
| Android | Requested via permission_handler |
| Windows | Not needed (desktop) |
| Linux | Not needed (desktop) |

## 7. Platform-Specific UI

| Feature | Android | Windows | Linux |
|---------|:-------:|:-------:|:-----:|
| TV cursor (D-pad) | ✅ default | ❌ | ❌ |
| Sync in background | ✅ WorkManager | ❌ | ❌ |
| TV cursor setting | ✅ in Settings | ❌ hidden | ❌ hidden |

## 8. Decryption (decrypt_util.dart, book_decryption_service.dart)

- Uses `cryptography` + `cryptography_flutter` (when present)
- Same logic on all platforms
- cryptography_flutter: Android/iOS native; Windows/Linux fallback to pure Dart

## 9. API Service (api_service.dart)

- Same API calls on all platforms
- Device ID from DeviceIdHelper (platform-specific)
- No platform-specific API logic

## 10. Sync Screen (sync_screen.dart)

- Same flow on all platforms
- "Sync in background" only on Android (WorkManager)
- Course selection, download, retry: same on all platforms

## Verification Checklist

- [x] main.dart: Platform checks for sqflite, WebView, full screen
- [x] device_id_helper: Android/Win/Linux paths with device-specific IDs
- [x] MainActivity.kt: IMEI/androidId for Android
- [x] reading_screen: Windows path handling in _fileUrlToPath
- [x] file_browser: Windows drives, Linux roots, Android storage
- [x] settings_screen: Permission request only for Android
- [x] sync_screen: Background sync only for Android
- [x] No fixed/hardcoded device IDs

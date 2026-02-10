# Release APK: works in debug but stops when installed

If the app works with `flutter run` (debug) but fails or stops when you install the release APK, try the following.

## Changes made for release

1. **Network / WebView (book reader)**  
   `android/app/src/main/res/xml/network_security_config.xml` includes a `base-config` with `cleartextTrafficPermitted="true"` so the WebView can load `http://127.0.0.1` in release (local HTTP server for the book reader). Domains 127.0.0.1, localhost, 10.0.2.2, and ::1 are also explicitly allowed.

2. **ProGuard**  
   `android/app/proguard-rules.pro` has keep rules for Flutter, WebView, SharedPreferences, and crypto so nothing required is stripped. Minification is disabled for release (`isMinifyEnabled = false`) so these apply only if you enable it later.

## Capture logs from the release APK

1. Install the release APK and reproduce the issue.
2. With the device connected (USB or same network with `adb connect`), run:
   ```bash
   adb logcat -s flutter
   ```
   Or to see server/reading errors:
   ```bash
   adb logcat | grep -E "flutter|READING|SERVER|Exception|Error"
   ```
3. Check the output for the exact error (crash, exception, or missing resource).

## Other checks

- **Permissions** – After installing a new build, grant the same permissions as in debug (e.g. storage, "All files access" if prompted).
- **Battery optimization** – On some devices, disable battery optimization for the app so it is not killed in the background.

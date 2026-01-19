# Android TV Crash Fixes

## Issues Fixed

### 1. Missing Android TV Launcher Category
**Problem:** App not appearing in Android TV launcher
**Fix:** Added `LEANBACK_LAUNCHER` category to intent-filter

### 2. Missing TV Feature Declarations
**Problem:** App might not be recognized as TV-compatible
**Fix:** Added TV feature declarations (leanback, touchscreen optional)

### 3. Missing TV Banner
**Problem:** App might not display properly on TV home screen
**Fix:** Added banner attribute to activity

## Additional Fixes Needed

### 4. Runtime Permissions (Potential Issue)
The `file_picker` package might crash on Android TV if permissions aren't handled properly. Consider:

- Adding runtime permission requests
- Handling permission denials gracefully
- Using alternative file selection for TV (if file_picker doesn't work)

### 5. WebView on Android TV
WebView might have issues on some Android TV devices. Consider:
- Testing WebView initialization
- Adding error handling for WebView crashes
- Using alternative rendering if needed

## Testing Checklist

1. ✅ Build new APK with fixes
2. ⏳ Install on Android TV device
3. ⏳ Check if app appears in TV launcher
4. ⏳ Test app launch
5. ⏳ Test folder picker (might need alternative on TV)
6. ⏳ Test WebView book reading
7. ⏳ Check logcat for any errors

## Common Android TV Issues

### File Picker on TV
- `file_picker` might not work well on Android TV
- Consider using Storage Access Framework (SAF) instead
- Or use a text input for path entry on TV

### Remote Control Navigation
- Ensure all UI elements are focusable
- Test D-pad navigation
- Add proper focus handling

### Performance
- TV devices might have limited resources
- Optimize image loading
- Reduce memory usage

## Next Steps if Still Crashing

1. **Get Logcat Output:**
   ```bash
   adb logcat | grep -i "tv_app_books\|flutter\|crash"
   ```

2. **Check Specific Errors:**
   - Permission denied errors
   - WebView initialization errors
   - File access errors
   - Memory issues

3. **Test Components Individually:**
   - Remove file_picker temporarily
   - Test without WebView
   - Test with minimal UI

4. **Add Error Handling:**
   - Wrap file_picker calls in try-catch
   - Add WebView error handlers
   - Add permission request handlers

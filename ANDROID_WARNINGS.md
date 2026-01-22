# Android System Warnings

## SELinux Warnings (Harmless)

You may see warnings like these in logcat:

```
E/libc: Access denied finding property "media.metrics.enabled"
SELinux: Access denied for media_prop
```

### What They Are:
- **System-level warnings** from Android's media framework
- **Not errors** - they don't break app functionality
- **Common in all Android apps** - especially those using WebView
- **SELinux security warnings** - Android's security system blocking access to certain system properties

### Why They Appear:
1. **WebView** tries to access media metrics for performance tracking
2. **System components** attempt to read media-related properties
3. **Android's security model** (SELinux) blocks these accesses for security
4. **Normal behavior** - Android intentionally restricts access to system properties

### Impact:
- ✅ **No functional impact** - app works normally
- ✅ **No user-visible issues** - these are internal warnings
- ✅ **Safe to ignore** - they're informational only

### Can We Fix Them?
- ❌ **Not fixable** - these are system-level restrictions
- ❌ **Not necessary** - they don't affect app functionality
- ✅ **Can be filtered** - use logcat filters to hide them if needed

### Logcat Filtering:
To hide these warnings in logcat:

```bash
# Filter out SELinux and libc warnings
adb logcat | grep -v "SELinux\|libc.*Access denied"
```

Or use Android Studio's logcat filter:
- Add filter: `-tag:SELinux -tag:libc`

### Related Warnings:
- `media.metrics.enabled` - Media performance metrics
- `media_prop` - Media-related system properties
- These are all **harmless** and can be ignored

## Conclusion

These warnings are **normal Android system behavior** and can be safely ignored. They don't indicate any problems with the app and don't affect functionality.

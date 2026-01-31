# Use Cases & Validation Checks

This document outlines all the validation checks and use cases implemented in the app, similar to the storage device connection check.

## ✅ Implemented Checks

### 1. **Storage Device Connection Check** ✅
**When:** On home screen (bookshelf)
**Why:** Books are stored on external USB drive/external storage. If disconnected, books can't be accessed.
**Implementation:**
- Checks if configured storage location exists and is accessible
- Blocks book display if storage is not connected
- Shows clear message with storage path
- Provides "Retry" and "Settings" buttons

**User Experience:**
- ❌ **Without USB Drive:** Shows message "Storage device not connected. Please connect the configured storage device to access your books."
- ✅ **With USB Drive:** Books load normally

---

### 2. **Internet Connectivity Check** ✅
**When:** 
- Before license validation/activation
- Before starting online sync
- Before starting offline sync (to fetch book list from API)

**Why:** 
- License validation requires API calls
- Book downloading requires internet
- Even offline sync needs internet initially to get the book list

**Implementation:**
- Checks internet connectivity using DNS lookup
- Shows error message if internet is not available
- Prevents API calls that would fail anyway

**User Experience:**
- ❌ **No Internet during Activation:** "Internet connection required for license activation. Please check your network connection."
- ❌ **No Internet during Sync:** "Internet connection required for online sync. Please check your network connection and try again."
- ✅ **With Internet:** Normal operation

---

## 📋 Suggested Additional Use Cases

### 3. **License Expiry Check** 🔄 (Partially Implemented)
**When:** On app start, before displaying books
**Current:** Checks expiry date but could be improved
**Enhancement Needed:**
- Show expiry warning (e.g., "License expires in 7 days")
- Block access if expired
- Periodic check in background

**Recommended Implementation:**
- Check license expiry before loading bookshelf
- Show countdown or expiry warning
- Auto-deactivate if expired

---

### 4. **File Path Validation** 📁 (Suggested)
**When:** When opening a book from bookshelf
**Why:** File might have been deleted, moved, or storage disconnected
**Current Status:** Bookshelf shows books, but opening might fail silently

**Recommended Implementation:**
```dart
// Before opening book
if (!await File(book.filePath).exists()) {
  // Show error: "Book file not found. Please re-sync."
  // Mark book as unavailable in UI
  // Allow re-download option
}
```

**Benefits:**
- Prevent crashes when opening books
- Show which books are unavailable
- Allow re-syncing specific books

---

### 5. **Disk Space Check** 💾 (Suggested)
**When:** Before starting download/sync
**Why:** External storage might be full, causing download failures
**Implementation:**
```dart
// Check available space before download
final storage = await Directory(storageLocation).stat();
final requiredSpace = calculateRequiredSpace(books);
if (storage.availableSpace < requiredSpace) {
  // Warn user: "Insufficient storage space. Please free up space."
}
```

**Benefits:**
- Prevent incomplete downloads
- Inform user before starting long downloads
- Better error handling

---

### 6. **Sync Status Validation** 🔄 (Suggested)
**When:** On app start, before showing books
**Why:** Detect partial/failed syncs
**Implementation:**
- Check if all books in database have valid file paths
- Identify books downloaded but not in database
- Identify books in database but missing files
- Show sync status indicator

**Recommended Features:**
- Sync status badge (Complete/Incomplete/Failed)
- Option to retry failed downloads
- Clear indication of sync health

---

### 7. **API Server Availability** 🌐 (Suggested)
**When:** Before license activation, before sync
**Why:** Server might be down or unreachable
**Current:** Generic network error messages
**Enhancement:**
```dart
// Check if API server is reachable
final serverReachable = await ConnectivityHelper.checkHostReachable('burlington-celp.adurox.com');
if (!serverReachable) {
  // Show: "Server unavailable. Please try again later."
}
```

**Benefits:**
- Differentiate between "no internet" and "server down"
- Better error messages for users
- Retry logic improvements

---

### 8. **Token Validity Check** 🔑 (Suggested)
**When:** Before API calls that require authentication
**Why:** Token might have expired, causing silent failures
**Implementation:**
- Check token expiry before API calls
- Validate token format/structure
- Auto-refresh token if possible
- Show clear error if token invalid

---

### 9. **Permission Status Check** 🔐 (Partially Implemented)
**When:** Before accessing storage, before file operations
**Current:** Permission requests exist but could be enhanced
**Enhancement:**
- Periodic permission status check
- Clear indication when permissions denied
- Better guidance for manual permission grant

---

### 10. **App Update Check** 📱 (Optional)
**When:** On app start (optional feature)
**Why:** New versions might have bug fixes or features
**Implementation:**
- Check for app updates (if update server exists)
- Show update notification (non-blocking)
- Allow update from app settings

---

## 🎯 Priority Recommendations

### **High Priority (Critical)**
1. ✅ **Storage Connection Check** - IMPLEMENTED
2. ✅ **Internet Connectivity Check** - IMPLEMENTED
3. 🔄 **File Path Validation** - Should implement before opening books
4. 🔄 **License Expiry Check** - Enhance current implementation

### **Medium Priority (Important)**
5. **Sync Status Validation** - Improve user experience
6. **Disk Space Check** - Prevent failed downloads
7. **Token Validity Check** - Better error handling

### **Low Priority (Nice to Have)**
8. **API Server Availability** - Better error messages
9. **App Update Check** - Optional feature
10. **Permission Status Monitoring** - Enhanced UX

---

## 🔄 Workflow Summary

### **Online Mode (Internet Required)**
1. License Activation → ✅ Internet Check → Validate → Activate
2. Online Sync → ✅ Internet Check → ✅ Storage Check → Download Books
3. Reading Books → ✅ Storage Check (no internet needed) → Open from local files

### **Offline Mode (No Internet Required)**
1. Offline Sync → ⚠️ Internet initially needed for book list → Then scan storage
2. Reading Books → ✅ Storage Check → Open from local files
3. Bookshelf → ✅ Storage Check → Display books from database

---

## 💡 Key Insight

**Internet is required:**
- ✅ License validation/activation
- ✅ Getting product list (even for offline sync)
- ✅ Downloading books

**Internet is NOT required:**
- ✅ Reading downloaded books
- ✅ Browsing bookshelf
- ✅ Viewing book content (once files are on external storage)

**Storage is required:**
- ✅ Reading books (files must be on configured storage)
- ✅ Downloading books (save location)
- ✅ Offline sync (scan location)

**Storage is NOT required:**
- ✅ License activation (only if storing files)
- ✅ Viewing empty bookshelf (but no books to read)

---

## 🎨 UI/UX Recommendations

1. **Status Indicators:** Show connection status icons (Internet ✅/❌, Storage ✅/❌)
2. **Retry Buttons:** Always provide easy retry options
3. **Error Messages:** Be specific about what's wrong and how to fix it
4. **Offline Mode Badge:** Show when app is working offline
5. **Progress Indicators:** Show what's being checked (Checking internet... Checking storage...)

---

## 📝 Implementation Status

| Check | Status | Priority | Notes |
|-------|--------|----------|-------|
| Storage Connection | ✅ Done | High | Implemented with retry |
| Internet Connectivity | ✅ Done | High | Implemented before API calls |
| License Expiry | 🔄 Partial | High | Basic check exists, needs enhancement |
| File Path Validation | ❌ Not Done | High | Should add before opening books |
| Disk Space Check | ❌ Not Done | Medium | Useful before large downloads |
| Sync Status | ❌ Not Done | Medium | Would improve UX significantly |
| Token Validity | ❌ Not Done | Medium | Better error handling |
| Server Availability | ❌ Not Done | Low | Nice to have |

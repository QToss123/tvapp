# Loading Books from External Storage

The app now supports loading books from external storage devices (USB drives, SD cards, etc.) attached to your TV.

## How to Use

### 1. Prepare Your External Storage

Organize your books on the external device in the same folder structure:
```
/storage/XXXX-XXXX/  (or /mnt/media_rw/XXXX-XXXX/)
  └── books/
      ├── book1/
      │   ├── index.html
      │   ├── css/
      │   ├── js/
      │   └── ...
      └── book2/
          ├── index.html
          └── ...
```

### 2. Find Your External Storage Path

On Android TV, external storage paths are typically:
- **USB Drive**: `/storage/XXXX-XXXX/` or `/mnt/media_rw/XXXX-XXXX/`
- **SD Card**: `/storage/XXXX-XXXX/`
- The `XXXX-XXXX` is the device's unique identifier

You can find the path by:
- Using a file manager app on your TV
- Checking Android logs: `adb logcat | grep -i storage`
- Using the app's file browser (if implemented)

### 3. Set the Book's contentUrl

In your book data, use a `file://` URL pointing to the index.html:

```dart
Book(
  title: 'My External Book',
  author: 'Author Name',
  progress: 0,
  contentUrl: 'file:///storage/XXXX-XXXX/books/book1/index.html',
)
```

### 4. Example Paths

**USB Drive:**
```
file:///storage/1234-5678/books/book1/index.html
```

**SD Card:**
```
file:///storage/ABCD-EFGH/books/book1/index.html
```

**Alternative path format:**
```
file:///mnt/media_rw/1234-5678/books/book1/index.html
```

## Important Notes

1. **Permissions**: The app needs storage permissions to read from external devices
2. **Path Format**: Always use `file://` protocol with absolute paths
3. **Base URL**: The app automatically sets the base URL to the book's directory, so CSS/JS files will load correctly
4. **Case Sensitivity**: File paths are case-sensitive on Android

## Troubleshooting

- **File not found**: Check that the path is correct and the device is mounted
- **CSS/JS not loading**: The app automatically injects a `<base>` tag to ensure relative paths work
- **Permission denied**: Ensure the app has storage permissions in Android settings

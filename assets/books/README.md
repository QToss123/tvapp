# Books Storage Guide

This folder is where you can place your book files. The app supports multiple ways to store and load books:

## Option 1: Book Folders with index.html (Recommended)

Organize each book in its own folder with an `index.html` file:
```
assets/books/
  ├── book1/
  │   └── index.html
  ├── book2/
  │   └── index.html
  └── book3/
      └── index.html
```

Then reference the folder path in your book data (the app will automatically load index.html):
```dart
contentUrl: 'assets/books/book1'  // Automatically loads index.html
// or
contentUrl: 'assets/books/book1/'  // Also works with trailing slash
```

**Note:** The app automatically appends `/index.html` if you provide a folder path without a file extension.

## Option 2: Single HTML Files

You can also place HTML files directly in this folder:
```
assets/books/
  ├── book1.html
  ├── book2.html
  └── book3.html
```

Then reference them in your book data using:
```dart
contentUrl: 'assets/books/book1.html'
```

## Option 2: Network URLs

If your books are hosted online, use the full URL:
```dart
contentUrl: 'https://example.com/books/book1.html'
```

## Option 3: Local File System (For downloaded books)

For books stored on the device's file system, you'll need to use the `path_provider` package and reference files like:
```dart
contentUrl: 'file:///path/to/book.html'
```

## Supported Formats

The WebView can display:
- **HTML files** (.html) - Recommended format
- **Online web pages** - Any URL that serves HTML content
- **EPUB** - If converted to HTML or served via a web service

## Example Book Structure

For HTML books, structure them like this:
```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Book Title</title>
  <style>
    body {
      font-family: serif;
      max-width: 800px;
      margin: 0 auto;
      padding: 20px;
      line-height: 1.8;
    }
  </style>
</head>
<body>
  <h1>Chapter 1</h1>
  <p>Your book content here...</p>
</body>
</html>
```

## Notes

- Make sure to add your book files to `pubspec.yaml` under `flutter: assets:`
- For large books, consider hosting them online instead of bundling
- The app will automatically handle loading from assets, network, or local files

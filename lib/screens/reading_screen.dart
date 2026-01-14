import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/book.dart';

class ReadingScreen extends StatefulWidget {
  final Book book;

  const ReadingScreen({
    super.key,
    required this.book,
  });

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(true)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint('JavaScript message: ${message.message}');
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _error = null;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            // Only show error for main page load, ignore resource errors (they're logged but not critical)
            // Resource errors (like missing audio/images) are logged but don't break the page
            if (error.isForMainFrame == true) {
              setState(() {
                _isLoading = false;
                _error = error.description;
              });
            }
            // Log non-critical resource errors for debugging but don't show to user
            if (error.isForMainFrame != true) {
              debugPrint('Resource load error (non-critical): ${error.url} - ${error.description}');
            }
          },
        ),
      );

    // Load book content URL or show a placeholder
    if (widget.book.contentUrl != null && widget.book.contentUrl!.isNotEmpty) {
      final originalUrl = widget.book.contentUrl!;
      final contentUrl = _normalizeContentUrl(originalUrl);
      
      debugPrint('Original contentUrl: $originalUrl');
      debugPrint('Normalized contentUrl: $contentUrl');
      
      // Check if it's a local asset (starts with 'assets/')
      if (contentUrl.startsWith('assets/')) {
        debugPrint('Loading as asset: $contentUrl');
        _loadAsset(contentUrl);
      } else if (contentUrl.startsWith('file://')) {
        // Local file system (including external storage like USB drives)
        debugPrint('Loading as file: $contentUrl');
        _loadFile(contentUrl);
      } else if (contentUrl.startsWith('http://') || contentUrl.startsWith('https://')) {
        // Network URL
        debugPrint('Loading as network URL: $contentUrl');
        _controller.loadRequest(Uri.parse(contentUrl));
      } else {
        // Try as asset first, then as network URL
        debugPrint('Trying as asset: $contentUrl');
        _loadAsset(contentUrl);
      }
    } else {
      // Load a placeholder HTML if no URL is provided
      debugPrint('No contentUrl provided, loading placeholder');
      _controller.loadHtmlString(_getPlaceholderHtml());
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Normalizes the content URL to handle book folders.
  /// If the URL points to a folder (ends with / or no file extension),
  /// it automatically appends 'index.html'
  String _normalizeContentUrl(String url) {
    // If it's a network URL or file:// URL, don't modify
    if (url.startsWith('http://') || 
        url.startsWith('https://') || 
        url.startsWith('file://')) {
      // For network/file URLs, if it ends with /, append index.html
      if (url.endsWith('/')) {
        return url + 'index.html';
      }
      return url;
    }
    
    // For asset paths
    // Remove trailing slash if present
    String normalized = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    
    // Check if it already has a file extension
    if (normalized.contains('.')) {
      // Has extension, use as is
      return normalized;
    }
    
    // No extension, assume it's a folder and append /index.html
    return '$normalized/index.html';
  }

  Future<void> _loadAsset(String assetPath) async {
    debugPrint('Loading asset: $assetPath');
    
    try {
      // Load HTML as string to inject base tag for proper relative resource resolution
      // This ensures CSS, JS (including PDF.js), and other resources load correctly
      debugPrint('Loading HTML content: $assetPath');
      final String htmlContent = await DefaultAssetBundle.of(context)
          .loadString(assetPath);
      debugPrint('Successfully loaded HTML content (${htmlContent.length} chars)');
      
      // Extract base path for relative resources (directory containing the file)
      final basePath = assetPath.contains('/') 
          ? assetPath.substring(0, assetPath.lastIndexOf('/') + 1)
          : '';
      
      debugPrint('Base path: $basePath');
      
      // Inject base tag into HTML to ensure relative resources load correctly
      // This is critical for PDF.js, CSS, and other JS files to load
      String modifiedHtml = htmlContent;
      if (!modifiedHtml.contains('<base')) {
        // Find the head tag and insert base tag right after it
        final headIndex = modifiedHtml.indexOf('<head>');
        if (headIndex != -1) {
          final insertIndex = headIndex + 6; // After '<head>'
          // For Android assets, use the flutter_assets path
          // The base href must end with a slash for proper resolution
          final baseHref = 'file:///android_asset/flutter_assets/$basePath';
          modifiedHtml = modifiedHtml.substring(0, insertIndex) +
              '\n    <base href="$baseHref">' +
              modifiedHtml.substring(insertIndex);
          debugPrint('Injected base tag with href: $baseHref');
        } else {
          debugPrint('Warning: <head> tag not found, cannot inject base tag');
        }
      } else {
        debugPrint('Base tag already exists in HTML');
      }
      
      // Load HTML with base URL for relative resources
      // The baseUrl parameter ensures relative paths resolve correctly
      final baseUrl = basePath.isNotEmpty 
          ? 'file:///android_asset/flutter_assets/$basePath'
          : 'file:///android_asset/flutter_assets/';
      
      debugPrint('Loading with base URL: $baseUrl');
      
      await _controller.loadHtmlString(
        modifiedHtml,
        baseUrl: baseUrl,
      );
      
      debugPrint('Successfully loaded HTML with base URL - CSS/JS should now load correctly');
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Failed to load asset: $e');
      setState(() {
        _isLoading = false;
        _error = 'Failed to load book from $assetPath\n\n'
            'Error: $e\n\n'
            'Make sure:\n'
            '1. The file exists: $assetPath\n'
            '2. pubspec.yaml includes: assets/books/\n'
            '3. Run "flutter pub get"\n'
            '4. Run "flutter clean" and rebuild\n'
            '5. Restart the app completely (not hot reload)';
      });
    }
  }

  /// Loads a file from external storage (USB drive, SD card, etc.)
  /// Handles file:// URLs and ensures CSS/JS resources load correctly
  Future<void> _loadFile(String fileUrl) async {
    try {
      debugPrint('Loading file from external storage: $fileUrl');
      
      // Parse the file:// URL
      final uri = Uri.parse(fileUrl);
      final filePath = uri.path;
      final file = File(filePath);
      
      // Check if file exists
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }
      
      debugPrint('File exists, reading content from: $filePath');
      
      // Read HTML content
      final String htmlContent = await file.readAsString();
      debugPrint('Successfully read HTML content (${htmlContent.length} chars)');
      
      // Extract directory path for base URL
      final fileDir = file.parent.path;
      // Ensure path ends with slash for proper base URL
      final basePath = fileDir.endsWith('/') ? fileDir : '$fileDir/';
      
      debugPrint('Base path: $basePath');
      
      // Inject base tag into HTML to ensure relative resources load correctly
      String modifiedHtml = htmlContent;
      if (!modifiedHtml.contains('<base')) {
        final headIndex = modifiedHtml.indexOf('<head>');
        if (headIndex != -1) {
          final insertIndex = headIndex + 6; // After '<head>'
          // Use file:// protocol for the base href
          final baseHref = 'file://$basePath';
          modifiedHtml = modifiedHtml.substring(0, insertIndex) +
              '\n    <base href="$baseHref">' +
              modifiedHtml.substring(insertIndex);
          debugPrint('Injected base tag with href: $baseHref');
        }
      }
      
      // Load HTML with base URL pointing to the file's directory
      // This ensures CSS, JS, and other relative resources load correctly
      final baseUrl = 'file://$basePath';
      debugPrint('Loading with base URL: $baseUrl');
      
      await _controller.loadHtmlString(
        modifiedHtml,
        baseUrl: baseUrl,
      );
      
      debugPrint('Successfully loaded file from external storage');
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Failed to load file: $e');
      setState(() {
        _isLoading = false;
        _error = 'Failed to load book from external storage\n\n'
            'File: $fileUrl\n'
            'Error: $e\n\n'
            'Make sure:\n'
            '1. The file exists at the specified path\n'
            '2. The device has read permissions\n'
            '3. The path is correct (e.g., file:///storage/XXXX-XXXX/books/book1/index.html)';
      });
    }
  }

  String _getPlaceholderHtml() {
    return '''
    <!DOCTYPE html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        body {
          font-family: Arial, sans-serif;
          max-width: 800px;
          margin: 0 auto;
          padding: 20px;
          line-height: 1.6;
        }
        h1 { color: #333; }
        .author { color: #666; font-style: italic; }
      </style>
    </head>
    <body>
      <h1>${widget.book.title}</h1>
      <p class="author">by ${widget.book.author}</p>
      <hr>
      <p>Book content will be loaded here. Please provide a content URL for this book.</p>
      <p>This is a placeholder page. In a real application, you would load the actual book content from a URL or local file.</p>
    </body>
    </html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: () {
              if (widget.book.contentUrl != null &&
                  widget.book.contentUrl!.isNotEmpty) {
                _controller.reload();
              } else {
                _controller.loadHtmlString(_getPlaceholderHtml());
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_error != null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading content',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error ?? 'Unknown error',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (widget.book.contentUrl != null &&
                          widget.book.contentUrl!.isNotEmpty) {
                        _controller.reload();
                      } else {
                        _controller.loadHtmlString(_getPlaceholderHtml());
                      }
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          else
            WebViewWidget(controller: _controller),
          if (_isLoading && _error == null)
            Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading book content...'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

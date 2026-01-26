import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/book.dart';
import '../utils/zip_handler.dart';

/// Intent for TV remote key directions
class DirectionIntent extends Intent {
  final String dir;
  const DirectionIntent(this.dir);
}

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
  HttpServer? _localServer; // Local HTTP server for serving book files
  int _serverPort = 8080; // Port for local server
  final FocusNode _webViewFocusNode = FocusNode(); // Focus node for WebView (TV navigation)

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    // Request focus after first frame (for TV navigation)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _webViewFocusNode.requestFocus();
        debugPrint('🎮 [READING] WebView focus requested on init');
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Request focus when screen becomes visible (for TV navigation)
    if (!_isLoading && _error == null) {
      _requestWebViewFocus();
    }
  }

  @override
  void dispose() {
    // Stop local HTTP server
    _stopLocalServer();
    // Dispose focus node
    _webViewFocusNode.dispose();
    super.dispose();
  }

  /// Requests focus on the WebView for TV remote navigation
  void _requestWebViewFocus() {
    // Request focus after a short delay to ensure WebView is ready
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && _webViewFocusNode.canRequestFocus) {
        _webViewFocusNode.requestFocus();
        debugPrint('🎮 [READING] WebView focus requested for TV remote navigation');
      }
    });
  }

  /// Sends TV remote key events to the WebView via JavaScript
  /// Up/Down/Left/Right -> move visible cursor. Enter -> click at cursor.
  /// Shortcut: Left/Right also trigger prev/next when cursor is over reader area (optional).
  Future<void> _sendKeyToWeb(String direction) async {
    try {
      debugPrint('🎮 [READING] Sending key to WebView: $direction');
      
      String jsCode;
      if (direction == 'enter') {
        jsCode = "if(window.__tvClickAtCursor) window.__tvClickAtCursor();";
      } else if (direction == 'up' || direction == 'down' || direction == 'left' || direction == 'right') {
        jsCode = "if(window.__tvMoveCursor) window.__tvMoveCursor('$direction');";
      } else {
        return;
      }
      
      await _controller.runJavaScript(jsCode);
    } catch (e) {
      debugPrint('❌ [READING] Error sending key to WebView: $e');
    }
  }

  /// Injects JavaScript: visible TV cursor, focus styles, and prev/next mapping
  Future<void> _enableKeyboardNavigation() async {
    try {
      const jsCode = r'''
        (function() {
          var step = 32;
          var cursor = document.createElement('div');
          cursor.id = 'tv-cursor';
          cursor.style.cssText = 'position:fixed;width:28px;height:28px;border-radius:50%;border:3px solid #4F46E5;background:rgba(79,70,229,0.2);pointer-events:none;z-index:2147483647;left:50%;top:50%;transform:translate(-50%,-50%);transition:left 0.05s, top 0.05s;box-shadow:0 2px 8px rgba(0,0,0,0.3);';
          document.body.appendChild(cursor);
          var r = cursor.getBoundingClientRect();
          var x = (window.innerWidth / 2) - 14;
          var y = (window.innerHeight / 2) - 14;
          function updateCursor() {
            cursor.style.left = Math.max(0, Math.min(window.innerWidth - 28, x)) + 'px';
            cursor.style.top = Math.max(0, Math.min(window.innerHeight - 28, y)) + 'px';
            cursor.style.transform = 'none';
          }
          updateCursor();
          window.__tvMoveCursor = function(dir) {
            if (dir === 'up') y -= step;
            else if (dir === 'down') y += step;
            else if (dir === 'left') x -= step;
            else if (dir === 'right') x += step;
            updateCursor();
          };
          window.__tvClickAtCursor = function() {
            var cx = x + 14;
            var cy = y + 14;
            var el = document.elementFromPoint(cx, cy);
            while (el && el !== document.body) {
              var tag = (el.tagName || '').toLowerCase();
              if (tag === 'a' || tag === 'button' || el.onclick || el.getAttribute('onclick') || el.classList.contains('btn-control') || el.classList.contains('header-btn') || el.id === 'btn-prev' || el.id === 'btn-next') {
                el.click();
                return;
              }
              el = el.parentElement;
            }
            if (el && el !== document.body) el.click();
          };
          var style = document.createElement('style');
          style.textContent = '*:focus { outline: 3px solid #4F46E5 !important; outline-offset: 2px !important; }';
          document.head.appendChild(style);
          var btns = document.querySelectorAll('a, button, input, [tabindex], [onclick]');
          btns.forEach(function(el) { if (!el.tabIndex) el.setAttribute('tabindex', '0'); });
          console.log('TV cursor and keyboard nav enabled');
        })();
      ''';
      await _controller.runJavaScript(jsCode);
      debugPrint('✅ [READING] TV cursor and keyboard navigation enabled');
    } catch (e) {
      debugPrint('⚠️ [READING] Error enabling keyboard navigation: $e');
    }
  }

  /// Stops the local HTTP server
  Future<void> _stopLocalServer() async {
    if (_localServer != null) {
      try {
        debugPrint('🛑 [READING] Stopping local HTTP server on port $_serverPort...');
        await _localServer!.close(force: true);
        _localServer = null;
        debugPrint('✅ [READING] Local HTTP server stopped');
      } catch (e) {
        debugPrint('⚠️ [READING] Error stopping local server: $e');
      }
    }
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
            // Request focus on WebView after page loads (for TV remote navigation)
            _requestWebViewFocus();
            // Inject JavaScript to enable keyboard/D-pad navigation in HTML
            _enableKeyboardNavigation();
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
  /// Note: ZIP files are handled separately and don't need normalization here
  String _normalizeContentUrl(String url) {
    // If it's a network URL or file:// URL, don't modify
    if (url.startsWith('http://') || 
        url.startsWith('https://') || 
        url.startsWith('file://')) {
      // For ZIP files, return as is (will be handled in _loadFile)
      if (url.toLowerCase().endsWith('.zip')) {
        return url;
      }
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
      // Has extension, use as is (could be .html, .zip, etc.)
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
  /// Copies the book folder to internal storage first, then loads from there
  /// This bypasses Android 10+ file:// access restrictions
  /// Cleans up the copied folder when done
  Future<void> _loadFile(String fileUrl) async {
    try {
      debugPrint('📂 [READING] Loading file from external storage: $fileUrl');
      
      // Parse the file:// URL
      final uri = Uri.parse(fileUrl);
      var filePath = uri.path;
      var file = File(filePath);
      
      // Check if file exists
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }
      
      // Check if file is a ZIP and extract it if necessary
      debugPrint('📦 [READING] Checking if file is a ZIP: $filePath');
      final processed = await ZipHandler.processBookFile(filePath);
      filePath = processed.path;
      
      if (processed.wasExtracted) {
        debugPrint('📦 [READING] ZIP file was extracted to: $filePath');
      }
      
      // Determine the book directory
      Directory bookDirectory;
      String? indexHtmlPath;
      
      file = File(filePath);
      final isFile = await file.exists();
      final dir = Directory(filePath);
      final isDirectory = await dir.exists();
      
      if (isFile) {
        // It's a file (e.g., index.html), use its parent directory
        bookDirectory = file.parent;
        indexHtmlPath = filePath;
      } else if (isDirectory) {
        // It's a directory, look for index.html
        debugPrint('📂 [READING] Path is a directory, searching for index.html: $filePath');
        indexHtmlPath = await ZipHandler.findIndexHtml(filePath);
        
        if (indexHtmlPath == null) {
          throw Exception('No index.html found in directory: $filePath');
        }
        
        bookDirectory = Directory(filePath);
      } else {
        throw Exception('Path is neither a file nor a directory: $filePath');
      }
      
      debugPrint('📂 [READING] Book directory: ${bookDirectory.path}');
      debugPrint('📄 [READING] Index HTML: $indexHtmlPath');
      
      // Start local HTTP server to serve book files
      debugPrint('🚀 [READING] Starting local HTTP server...');
      await _startLocalServer(bookDirectory);
      
      // Calculate relative path to index.html from book directory
      final relativePath = path.relative(indexHtmlPath, from: bookDirectory.path);
      // Normalize path separators for URL
      final urlPath = relativePath.replaceAll('\\', '/');
      
      // Load book via localhost HTTP server
      final bookUrl = 'http://127.0.0.1:$_serverPort/$urlPath';
      debugPrint('🌐 [READING] Loading book via localhost: $bookUrl');
      debugPrint('✅ [READING] All resources (CSS, JS, audio) will load via HTTP server');
      
      await _controller.loadRequest(Uri.parse(bookUrl));
      
      debugPrint('✅ [READING] Successfully loaded book via local HTTP server');
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ [READING] Failed to load file: $e');
      // Clean up on error
      await _stopLocalServer();
      setState(() {
        _isLoading = false;
        _error = 'Failed to load book from external storage\n\n'
            'File: $fileUrl\n'
            'Error: $e\n\n'
            'Make sure:\n'
            '1. The file exists at the specified path\n'
            '2. The device has read permissions\n'
            '3. The path is correct (e.g., file:///storage/XXXX-XXXX/books/book1/index.html or file:///storage/XXXX-XXXX/books/book1.zip)';
      });
    }
  }

  /// Starts a local HTTP server to serve book files
  /// This bypasses Android 10+ file:// access restrictions
  Future<void> _startLocalServer(Directory bookDirectory) async {
    // Stop any existing server first
    await _stopLocalServer();
    
    // Try to find an available port starting from 8080
    for (int port = 8080; port < 8090; port++) {
      try {
        _serverPort = port;
        _localServer = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
        debugPrint('✅ [READING] Local HTTP server started on http://127.0.0.1:$port');
        break;
      } catch (e) {
        if (port == 8089) {
          throw Exception('Could not find available port for local server');
        }
        continue;
      }
    }
    
    // Handle incoming requests
    _localServer!.listen((HttpRequest request) async {
      try {
        // Get the requested path
        var requestedPath = request.uri.path;
        // Remove leading slash
        if (requestedPath.startsWith('/')) {
          requestedPath = requestedPath.substring(1);
        }
        
        // If root path, serve index.html
        if (requestedPath.isEmpty || requestedPath == '/') {
          requestedPath = 'index.html';
        }
        
        // Build full file path
        final filePath = path.join(bookDirectory.path, requestedPath);
        final file = File(filePath);
        
        debugPrint('📡 [SERVER] Request: ${request.uri.path} -> $filePath');
        
        if (await file.exists()) {
          // Determine content type
          String contentType = 'application/octet-stream';
          final ext = path.extension(filePath).toLowerCase();
          switch (ext) {
            case '.html':
              contentType = 'text/html; charset=utf-8';
              break;
            case '.css':
              contentType = 'text/css; charset=utf-8';
              break;
            case '.js':
              contentType = 'application/javascript; charset=utf-8';
              break;
            case '.json':
              contentType = 'application/json; charset=utf-8';
              break;
            case '.png':
              contentType = 'image/png';
              break;
            case '.jpg':
            case '.jpeg':
              contentType = 'image/jpeg';
              break;
            case '.gif':
              contentType = 'image/gif';
              break;
            case '.svg':
              contentType = 'image/svg+xml';
              break;
            case '.mp3':
              contentType = 'audio/mpeg';
              break;
            case '.mp4':
              contentType = 'video/mp4';
              break;
            case '.woff':
              contentType = 'font/woff';
              break;
            case '.woff2':
              contentType = 'font/woff2';
              break;
            case '.ttf':
              contentType = 'font/ttf';
              break;
          }
          
          // Read and serve file
          final fileBytes = await file.readAsBytes();
          request.response
            ..headers.contentType = ContentType.parse(contentType)
            ..headers.contentLength = fileBytes.length
            ..add(fileBytes)
            ..close();
          
          debugPrint('✅ [SERVER] Served: ${request.uri.path} (${fileBytes.length} bytes)');
        } else {
          // File not found
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('File not found: ${request.uri.path}')
            ..close();
          
          debugPrint('❌ [SERVER] File not found: ${request.uri.path}');
        }
      } catch (e) {
        debugPrint('❌ [SERVER] Error serving request: $e');
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Server error: $e')
          ..close();
      }
    });
    
    debugPrint('🌐 [READING] Server ready to serve files from: ${bookDirectory.path}');
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
        // Prevent AppBar from stealing focus on TV
        automaticallyImplyLeading: false,
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
            // Intercept TV remote keys and forward to WebView
            Shortcuts(
              shortcuts: <LogicalKeySet, Intent>{
                // D-pad navigation
                LogicalKeySet(LogicalKeyboardKey.arrowUp): const DirectionIntent('up'),
                LogicalKeySet(LogicalKeyboardKey.arrowDown): const DirectionIntent('down'),
                LogicalKeySet(LogicalKeyboardKey.arrowLeft): const DirectionIntent('left'),
                LogicalKeySet(LogicalKeyboardKey.arrowRight): const DirectionIntent('right'),
                // Enter/Select button
                LogicalKeySet(LogicalKeyboardKey.select): const DirectionIntent('enter'),
                LogicalKeySet(LogicalKeyboardKey.enter): const DirectionIntent('enter'),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  DirectionIntent: CallbackAction<DirectionIntent>(
                    onInvoke: (intent) {
                      _sendKeyToWeb(intent.dir);
                      return null;
                    },
                  ),
                },
                child: Focus(
                  focusNode: _webViewFocusNode,
                  autofocus: true,
                  skipTraversal: false,
                  child: WebViewWidget(controller: _controller),
                ),
              ),
            ),
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

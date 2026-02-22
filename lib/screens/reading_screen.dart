import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:path/path.dart' as path;
import '../models/book.dart';
import '../utils/zip_handler.dart';
import '../services/database_service.dart';
import '../utils/decrypt_util.dart';

/// Intent for TV remote key directions
class DirectionIntent extends Intent {
  final String dir;
  const DirectionIntent(this.dir);
}

/// Intent for keyboard scroll (Linux/desktop when mouse scroll doesn't work)
class ScrollIntent extends Intent {
  final int deltaY;
  const ScrollIntent(this.deltaY);
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

// No history for reader: we do not save or restore reading position/progress.
class _ReadingScreenState extends State<ReadingScreen> {
  static const _kTVCursorEnabled = 'tv_cursor_enabled';

  WebViewController? _controller;
  bool _isLoading = true;
  /// Shown during decrypt/unzip/open (opening, unlocking, preparing, loading)
  String? _loadingMessage;
  String? _error;
  HttpServer? _localServer;
  int _serverPort = 8080;
  final FocusNode _webViewFocusNode = FocusNode();
  /// Linux fallback: HTTP URL to retry if file:// fails
  String? _linuxHttpFallbackUrl;
  String? _decryptedCachePath;
  /// When true: TV cursor + D-pad key forwarding (Android TV). When false: plain WebView, no cursor (e.g. Windows).
  bool _useTvCursor = false;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _loadTvCursorSetting();
  }

  Future<void> _loadTvCursorSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final explicit = prefs.getBool(_kTVCursorEnabled);
      final bool use = explicit ?? Platform.isAndroid;
      if (mounted && _useTvCursor != use) {
        setState(() => _useTvCursor = use);
      } else {
        _useTvCursor = use;
      }
    } catch (_) {
      _useTvCursor = Platform.isAndroid;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Request focus for TV cursor (Android) or keyboard scroll (Linux/Windows)
    if (!_isLoading && _error == null && (_useTvCursor || Platform.isLinux || Platform.isWindows)) {
      _requestWebViewFocus();
    }
  }

  @override
  void dispose() {
    // Defer server close so WebView can finish teardown first (reduces crash on Back)
    final server = _localServer;
    _localServer = null;
    if (server != null) {
      Future.delayed(const Duration(milliseconds: 1200), () async {
        try {
          await server.close(force: true);
        } catch (_) { /* ignore */ }
      });
    }
    // Delete decrypted file from app cache (best-effort)
    if (_decryptedCachePath != null) {
      try {
        final f = File(_decryptedCachePath!);
        if (f.existsSync()) {
          f.deleteSync();
        }
      } catch (e) { /* ignore */ }
    }
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
      }
    });
  }

  /// Sends TV remote key events to the WebView via JavaScript
  /// Up/Down/Left/Right -> move visible cursor. Enter -> click at cursor.
  /// Shortcut: Left/Right also trigger prev/next when cursor is over reader area (optional).
  Future<void> _sendKeyToWeb(String direction) async {
    try {
      
      String jsCode;
      if (direction == 'enter') {
        jsCode = "if(window.__tvClickAtCursor) window.__tvClickAtCursor();";
      } else if (direction == 'up' || direction == 'down' || direction == 'left' || direction == 'right') {
        jsCode = "if(window.__tvMoveCursor) window.__tvMoveCursor('$direction');";
      } else {
        return;
      }
      
      await _controller?.runJavaScript(jsCode);
    } catch (e) { /* ignore */ }
  }

  /// Builds WebView for desktop (Windows/Linux). On Linux, adds keyboard scroll
  /// shortcuts because mouse scroll often doesn't work with webkit2gtk.
  Widget _buildDesktopWebView() {
    final c = _controller;
    if (c == null) return const SizedBox.shrink();
    if (!Platform.isLinux && !Platform.isWindows) {
      return WebViewWidget(controller: c);
    }
    const scrollAmount = 120;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown): ScrollIntent(scrollAmount),
        SingleActivator(LogicalKeyboardKey.arrowUp): ScrollIntent(-scrollAmount),
        SingleActivator(LogicalKeyboardKey.pageDown): ScrollIntent(400),
        SingleActivator(LogicalKeyboardKey.pageUp): ScrollIntent(-400),
        SingleActivator(LogicalKeyboardKey.space): ScrollIntent(400),
        SingleActivator(LogicalKeyboardKey.space, shift: true): ScrollIntent(-400),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ScrollIntent: CallbackAction<ScrollIntent>(
            onInvoke: (intent) {
              _scrollWebView(intent.deltaY);
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _webViewFocusNode,
          autofocus: true,
          child: Listener(
            onPointerDown: (_) => _webViewFocusNode.requestFocus(),
            child: WebViewWidget(controller: c),
          ),
        ),
      ),
    );
  }

  /// Scrolls the WebView content (used when mouse scroll doesn't work on Linux).
  /// Tries reader-view/reader-content first (EPUB viewer), then window.
  Future<void> _scrollWebView(int deltaY) async {
    try {
      final js = '''
        (function() {
          var el = document.getElementById('reader-view') || document.getElementById('reader-content') || document.scrollingElement || document.documentElement;
          if (el) el.scrollTop += $deltaY;
          else window.scrollBy(0, $deltaY);
        })();
      ''';
      await _controller?.runJavaScript(js);
    } catch (e) { /* ignore */ }
  }

  /// Injects fixes for page-jump input (Enter to apply), responsive zoom,
  /// and optionally hides Flash/SoundManager diagnostic (WebView has no Flash).
  Future<void> _injectBookFixes() async {
    try {
      const jsCode = r'''
        (function() {
          var inp = document.getElementById('page-jump-input');
          if (inp) {
            inp.addEventListener('keydown', function(e) {
              if (e.key === 'Enter' || e.keyCode === 13) {
                e.preventDefault();
                this.blur();
                this.dispatchEvent(new Event('change', { bubbles: true }));
              }
            });
          }
          var s = document.createElement('style');
          s.id = 'reader-responsive-fixes';
          s.textContent = [
            '#reader-view { max-width: 100vw; min-width: 0; box-sizing: border-box; overflow: auto !important; -webkit-overflow-scrolling: touch; }',
            '#reader-content { max-width: 100%; min-width: 0; box-sizing: border-box; overflow: auto !important; }',
            '.view-mode-single .page-container, .view-mode-double .page-container { max-width: 100% !important; box-sizing: border-box; }',
            '.page-container canvas, .page-container img { max-width: 100% !important; height: auto !important; object-fit: contain !important; }',
            'html, body { max-width: 100vw; overflow-x: hidden; overflow-y: auto !important; box-sizing: border-box; }',
            '#app { max-width: 100vw; min-width: 0; overflow-x: hidden; box-sizing: border-box; }',
            '#reader-content { padding-bottom: 120px !important; }',
            '#reader-view { padding-bottom: 0 !important; }'
          ].join('\n');
          if (!document.getElementById('reader-responsive-fixes')) document.head.appendChild(s);
          var walk = function(el, fn) {
            if (!el) return;
            if (fn(el)) return;
            var ch = el.children;
            for (var i = 0; ch && i < ch.length; i++) walk(ch[i], fn);
          };
          walk(document.body, function(el) {
            var t = (el.innerText || el.textContent || '').toLowerCase();
            if (t.indexOf('flash options') !== -1 && t.indexOf('soundmanager') !== -1) {
              el.style.display = 'none';
              return true;
            }
            return false;
          });
        })();
      ''';
      await _controller?.runJavaScript(jsCode);
    } catch (e) { /* ignore */ }
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
              if (tag === 'a' || tag === 'button' || tag === 'input' || el.onclick || el.getAttribute('onclick') || el.classList.contains('btn-control') || el.classList.contains('header-btn') || el.id === 'btn-prev' || el.id === 'btn-next' || el.id === 'page-jump-input') {
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
      await _controller?.runJavaScript(jsCode);
    } catch (e) { /* ignore */ }
  }

  /// Stops the local HTTP server
  Future<void> _stopLocalServer() async {
    if (_localServer != null) {
      try {
        await _localServer!.close(force: true);
        _localServer = null;
      } catch (e) { /* ignore */ }
    }
  }


  void _initializeWebView() {
    try {
      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..enableZoom(true)
        ..setBackgroundColor(Colors.white)
        ..addJavaScriptChannel(
          'FlutterChannel',
          onMessageReceived: (JavaScriptMessage message) {
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              if (mounted) setState(() {
                _isLoading = true;
                _error = null;
              });
            },
            onPageFinished: (String url) {
              _linuxHttpFallbackUrl = null;
              if (mounted) setState(() { _isLoading = false; _loadingMessage = null; });
              _injectBookFixes();
              if (_useTvCursor) {
                _requestWebViewFocus();
                _enableKeyboardNavigation();
              }
            },
            onWebResourceError: (WebResourceError error) {
              if (error.isForMainFrame == true) {
                final fallback = _linuxHttpFallbackUrl;
                final errUrl = error.url;
                if ((Platform.isLinux || Platform.isWindows) &&
                    fallback != null &&
                    (errUrl == null || errUrl.isEmpty || errUrl.startsWith('file://'))) {
                  _linuxHttpFallbackUrl = null;
                  if (mounted && _controller != null) {
                    _controller!.loadRequest(Uri.parse(fallback));
                  }
                  return;
                }
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                    _error = 'This book couldn’t be opened.';
                  });
                }
              }
            },
          ),
        );
      _controller = c;
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Couldn’t open the reader. Please try again.';
          _isLoading = false;
        });
      }
      return;
    }

    // Defer load so first frame paints (loading indicator) and UI thread stays responsive (avoids ANR)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controller == null) return;
      try {
        _startLoadingContent();
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = 'Couldn’t open this book. Please try again.';
            _isLoading = false;
          });
        }
      }
    });
  }

  void _startLoadingContent() {
    final c = _controller;
    if (c == null) return;
    if (widget.book.contentUrl == null || widget.book.contentUrl!.isEmpty) {
      c.loadRequest(Uri.parse('about:blank'));
      setState(() {
        _isLoading = false;
        _error = 'This book isn’t downloaded yet. Go to Sync to download it first.';
      });
      return;
    }
    final originalUrl = widget.book.contentUrl!;
    final contentUrl = _normalizeContentUrl(originalUrl);
    if (contentUrl.startsWith('assets/')) {
      _loadAsset(contentUrl);
    } else if (contentUrl.startsWith('file://')) {
      _loadFile(contentUrl);
    } else if (contentUrl.startsWith('http://') || contentUrl.startsWith('https://')) {
      c.loadRequest(Uri.parse(contentUrl));
    } else if (_looksLikeLocalPath(contentUrl)) {
      // Raw path (e.g. C:\path on Windows or /path) — treat as file
      final fileUrl = contentUrl.contains('://') ? contentUrl : 'file:///${contentUrl.replaceAll(r'\', '/')}';
      _loadFile(fileUrl);
    } else {
      _loadAsset(contentUrl);
    }
  }

  /// True if string looks like a local file path (Windows or POSIX).
  static bool _looksLikeLocalPath(String url) {
    if (url.isEmpty) return false;
    if (Platform.isWindows && url.length >= 2 && url[1] == ':') return true;
    if (url.startsWith('/') && !url.startsWith('//')) return true;
    return false;
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
    await _loadTvCursorSetting();
    try {
      // Load HTML as string to inject base tag for proper relative resource resolution
      // This ensures CSS, JS (including PDF.js), and other resources load correctly
      final String htmlContent = await DefaultAssetBundle.of(context)
          .loadString(assetPath);
      
      // Extract base path for relative resources (directory containing the file)
      final basePath = assetPath.contains('/') 
          ? assetPath.substring(0, assetPath.lastIndexOf('/') + 1)
          : '';
      
      
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
        } else {
        }
      } else {
      }
      
      // Load HTML with base URL for relative resources
      // The baseUrl parameter ensures relative paths resolve correctly
      final baseUrl = basePath.isNotEmpty 
          ? 'file:///android_asset/flutter_assets/$basePath'
          : 'file:///android_asset/flutter_assets/';
      
      
      await _controller?.loadHtmlString(
        modifiedHtml,
        baseUrl: baseUrl,
      );
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'This file could not be opened.';
      });
    }
  }

  /// Converts a file:// URL to a native filesystem path (handles Windows drive letters).
  static String _fileUrlToPath(String fileUrl) {
    // Normalize so Uri.parse works (e.g. file:///C:\path -> file:///C:/path)
    final normalizedUrl = fileUrl.replaceAll(r'\', '/');
    final uri = Uri.parse(normalizedUrl);
    var filePath = uri.path;
    if (Platform.isWindows &&
        filePath.length >= 3 &&
        filePath.startsWith('/') &&
        filePath[2] == ':' &&
        RegExp(r'^/[A-Za-z]:').hasMatch(filePath)) {
      filePath = filePath.substring(1);
    }
    if (Platform.isWindows) {
      filePath = filePath.replaceAll('/', path.separator);
    }
    return filePath;
  }

  /// Loads a file from external storage. Uses in-screen loader only (no blocking dialog).
  /// Loader is cleared when WebView finishes loading (onPageFinished).
  Future<void> _loadFile(String fileUrl) async {
    if (mounted) setState(() { _isLoading = true; _error = null; _loadingMessage = 'opening'; });
    await Future.delayed(Duration.zero); // Let loading indicator paint once

    // Show reader frame immediately on Android so user sees "Opening..." (skip on Windows/Linux to avoid blocking load)
    if (mounted && _controller != null && !Platform.isWindows && !Platform.isLinux) {
      _controller!.loadHtmlString(
        '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>'
        '<body style="display:flex;align-items:center;justify-content:center;height:100vh;margin:0;font-family:system-ui,sans-serif;color:#555;">'
        '<p style="font-size:1.1em;">Opening book…</p></body></html>',
      );
    }

    void showErr(String message) {
      if (mounted) setState(() { _isLoading = false; _error = message; _loadingMessage = null; });
    }

    try {
      await _loadTvCursorSetting();

      var filePath = _fileUrlToPath(fileUrl);
      var file = File(filePath);

      // Run file check and DB lookup in parallel for faster open
      final results = await Future.wait([
        file.exists(),
        DatabaseService.getBookByFilePath(filePath),
      ]);
      final fileExists = results[0] as bool;
      final dbBook = results[1] as Book?;

      if (!fileExists) {
        showErr('This book wasn’t found. It may have been moved or deleted.');
        return;
      }
      final encBookId = dbBook?.encBookId ?? widget.book.encBookId;
      final encKeyB64 = dbBook?.encKeyB64 ?? widget.book.encKeyB64;
      final encNonceB64 = dbBook?.encNonceB64 ?? widget.book.encNonceB64;

      // If encrypted: decrypt on click (not on bookshelf)
      final hasEncMeta = (encBookId != null && encBookId.isNotEmpty) ||
          (encKeyB64 != null && encKeyB64.isNotEmpty) ||
          (encNonceB64 != null && encNonceB64.isNotEmpty);
      if (hasEncMeta) {
        if (mounted) setState(() { _loadingMessage = 'unlocking'; });
        await Future.delayed(Duration.zero);
        await isDecryptedFileAvailable(
          encryptedFilePath: filePath,
          encBookId: encBookId ?? '',
        );

        try {
          final result = await decryptBookFileIfNeeded(
            encryptedFilePath: filePath,
            encBookId: encBookId,
            encKeyB64: encKeyB64,
            encNonceB64: encNonceB64,
          );
          filePath = result.pathToUse;
          _decryptedCachePath = result.pathToUse;
          file = File(filePath);
        } catch (e) {
          showErr('This book couldn’t be opened. It may be damaged or in the wrong format.');
          return;
        }
      }

      if (mounted) setState(() { _loadingMessage = 'preparing'; });
      ({String path, bool wasExtracted}) processed;
      try {
        processed = await ZipHandler.processBookFileOffMain(filePath);
        filePath = processed.path;
      } on FormatException catch (_) {
        showErr('Incorrect format.');
        return;
      }
      
      if (processed.wasExtracted) {
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
        indexHtmlPath = await ZipHandler.findIndexHtml(filePath);
        
        if (indexHtmlPath == null) {
          throw Exception('No index.html found in directory: $filePath');
        }
        
        bookDirectory = Directory(filePath);
      } else {
        throw Exception('Path is neither a file nor a directory: $filePath');
      }

      if (mounted) setState(() { _loadingMessage = 'loading'; });
      await _startLocalServer(bookDirectory);
      final relativePath = path.relative(indexHtmlPath, from: bookDirectory.path);
      final urlPath = relativePath.replaceAll('\\', '/');
      final httpUrl = 'http://127.0.0.1:$_serverPort/$urlPath';

      String bookUrl;
      if (Platform.isLinux || Platform.isWindows) {
        // Desktop: try file:// first so WebView doesn't hit localhost restrictions. Fallback to HTTP if it fails.
        bookUrl = Uri.file(indexHtmlPath).toString();
        _linuxHttpFallbackUrl = httpUrl;
      } else {
        _linuxHttpFallbackUrl = null;
        bookUrl = httpUrl;
      }

      if (Platform.isLinux || Platform.isWindows) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          _controller?.loadRequest(Uri.parse(bookUrl));
          // If file:// fails, onWebResourceError will retry with HTTP fallback
        });
      } else {
        // Android/Android TV: WebView is often not attached until after the dialog closes and a frame runs.
        // Post-frame + 300ms delay so the book opens reliably after decrypt/unzip.
        if (mounted) setState(() => _isLoading = true);
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await Future.delayed(const Duration(milliseconds: 300));
          if (!mounted) return;
          try {
            _controller?.loadRequest(Uri.parse(bookUrl));
          } catch (e) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _error = 'This book couldn’t be opened.';
              });
            }
          }
        });
      }
    } catch (e) {
      await _stopLocalServer();
      if (mounted) {
        final errorStr = e.toString().toLowerCase();
        final isFormatOrDecrypt = errorStr.contains('format') ||
            errorStr.contains('invalid zip') ||
            errorStr.contains('corrupt') ||
            errorStr.contains('decryption') ||
            errorStr.contains('secretbox') ||
            errorStr.contains('authentication') ||
            errorStr.contains('wrong mac') ||
            errorStr.contains('index.html');
        final String friendlyMessage =
            isFormatOrDecrypt ? 'This book couldn’t be opened. It may be damaged or in the wrong format.' : 'This book couldn’t be opened.';
        setState(() { _isLoading = false; _error = friendlyMessage; _loadingMessage = null; });
      }
    }
  }

  /// Resolves path case-insensitively so "css/file.css" finds "CSS/file.css" on Android.
  static Future<String?> _resolvePathCaseInsensitive(Directory dir, String relativePath) async {
    final parts = relativePath.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    String currentPath = dir.path;
    for (int i = 0; i < parts.length; i++) {
      final currentDir = Directory(currentPath);
      final name = parts[i];
      final direct = File(path.join(currentPath, name));
      if (await direct.exists()) {
        currentPath = direct.path;
        continue;
      }
      String? found;
      await for (final entity in currentDir.list(followLinks: false)) {
        if (entity.path.split(path.separator).last.toLowerCase() == name.toLowerCase()) {
          found = entity.path;
          break;
        }
      }
      if (found == null) return null;
      currentPath = found;
    }
    return currentPath;
  }

  /// Returns correct MIME type string so browsers accept CSS/JS (strict MIME checking).
  static String _mimeTypeForExtension(String ext) {
    switch (ext) {
      case '.html':
      case '.htm':
        return 'text/html; charset=utf-8';
      case '.css':
        return 'text/css; charset=utf-8';
      case '.js':
        return 'application/javascript; charset=utf-8';
      case '.json':
        return 'application/json; charset=utf-8';
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.svg':
        return 'image/svg+xml';
      case '.webp':
        return 'image/webp';
      case '.mp3':
        return 'audio/mpeg';
      case '.mp4':
        return 'video/mp4';
      case '.wav':
        return 'audio/wav';
      case '.woff':
        return 'font/woff';
      case '.woff2':
        return 'font/woff2';
      case '.ttf':
        return 'font/ttf';
      case '.xml':
        return 'application/xml; charset=utf-8';
      default:
        return 'application/octet-stream';
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
        // Get and normalize the requested path (decode URI, block traversal)
        var requestedPath = request.uri.path;
        if (requestedPath.startsWith('/')) {
          requestedPath = requestedPath.substring(1);
        }
        requestedPath = Uri.decodeComponent(requestedPath);
        if (requestedPath.contains('..')) {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..headers.set('Content-Type', 'text/plain; charset=utf-8')
            ..write('Invalid path')
            ..close();
          return;
        }
        if (requestedPath.isEmpty || requestedPath == '/') {
          requestedPath = 'index.html';
        }

        var filePath = path.join(bookDirectory.path, requestedPath);
        var file = File(filePath);
        if (!await file.exists()) {
          final resolved = await _resolvePathCaseInsensitive(bookDirectory, requestedPath);
          if (resolved != null) {
            filePath = resolved;
            file = File(filePath);
          }
        }

        if (await file.exists()) {
          var ext = path.extension(filePath).toLowerCase();
          if (ext.isEmpty && requestedPath.contains('.')) {
            ext = '.${requestedPath.split('.').last.toLowerCase()}';
          }
          final String mimeStr = _mimeTypeForExtension(ext);

          final fileBytes = await file.readAsBytes();
          final response = request.response;
          response.headers.set('Content-Type', mimeStr);
          response.headers.contentType = ContentType.parse(mimeStr);
          response.headers.contentLength = fileBytes.length;
          response.add(fileBytes);
          response.close();
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..headers.set('Content-Type', 'text/plain; charset=utf-8')
            ..write('File not found: ${request.uri.path}')
            ..close();
        }
      } catch (e) {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..headers.set('Content-Type', 'text/plain; charset=utf-8')
          ..write('Server error: $e')
          ..close();
      }
    });
    
  }

  // ignore: unused_element
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

  Future<void> _performBack() async {
    try {
      await _controller?.runJavaScript('''
        (function(){
          try {
            var el = document.querySelectorAll("audio, video");
            for (var i = 0; i < el.length; i++) {
              el[i].pause();
              el[i].currentTime = 0;
              el[i].removeAttribute("src");
              el[i].load();
            }
          } catch(e) {}
        })();
      ''');
    } catch (_) { /* ignore */ }
    await Future.delayed(const Duration(milliseconds: 150));
    try {
      await _controller?.loadRequest(Uri.parse('about:blank'));
    } catch (_) { /* ignore */ }
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // On Windows/Linux (desktop), WebView platform view draws on top of Flutter
    // overlays. Use AppBar so the back button is in a dedicated area above the WebView.
    final useAppBarForBack = Platform.isWindows || Platform.isLinux;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _performBack();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: useAppBarForBack
            ? AppBar(
                backgroundColor: Colors.black87,
                elevation: 4,
                iconTheme: const IconThemeData(color: Colors.white),
                title: const Text(
                  'Back to BookShelf',
                  style: TextStyle(color: Colors.white),
                ),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  tooltip: 'Back',
                  onPressed: () => _performBack(),
                ),
              )
            : null,
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
                      'Couldn’t load this book',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error ?? 'Something went wrong. Please try again.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        if (widget.book.contentUrl != null &&
                            widget.book.contentUrl!.isNotEmpty) {
                          setState(() => _error = null);
                          _controller?.reload();
                        } else {
                          Navigator.maybePop(context);
                        }
                      },
                      icon: Icon(
                        widget.book.contentUrl != null &&
                                widget.book.contentUrl!.isNotEmpty
                            ? Icons.refresh
                            : Icons.arrow_back,
                      ),
                      label: Text(
                        widget.book.contentUrl != null &&
                                widget.book.contentUrl!.isNotEmpty
                            ? 'Retry'
                            : 'Go back',
                      ),
                    ),
                  ],
                ),
              )
            else if (_controller != null)
              _useTvCursor
                  ? Shortcuts(
                      shortcuts: <LogicalKeySet, Intent>{
                        LogicalKeySet(LogicalKeyboardKey.arrowUp): const DirectionIntent('up'),
                        LogicalKeySet(LogicalKeyboardKey.arrowDown): const DirectionIntent('down'),
                        LogicalKeySet(LogicalKeyboardKey.arrowLeft): const DirectionIntent('left'),
                        LogicalKeySet(LogicalKeyboardKey.arrowRight): const DirectionIntent('right'),
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
                          child: WebViewWidget(controller: _controller!),
                        ),
                      ),
                    )
                  : _buildDesktopWebView(),
            if (_isLoading && _error == null)
              Container(
                color: Colors.white,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _loadingMessage == 'opening' || _loadingMessage == 'loading'
                            ? 'Opening your book…'
                            : _loadingMessage == 'unlocking'
                                ? 'Getting your book ready…'
                                : _loadingMessage == 'preparing'
                                    ? 'Almost there…'
                                    : 'Opening your book…',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                          letterSpacing: 0.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _loadingMessage == null
                            ? 'Getting everything ready'
                            : _loadingMessage == 'unlocking'
                                ? 'First time may take a little longer'
                                : 'Please wait',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!useAppBarForBack)
              Positioned(
                left: 16,
                top: MediaQuery.of(context).padding.top + 16,
                child: Tooltip(
                  message: 'Back',
                  child: Material(
                    elevation: 6,
                    shadowColor: Colors.black45,
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.maybePop(context),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.arrow_back, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:path/path.dart' as path;
import '../models/book.dart';
import '../utils/zip_handler.dart';
import '../utils/book_manifest.dart';
import '../services/database_service.dart';
import '../services/book_decryption_service.dart';
import '../services/book_server_isolate.dart' as isolate_runner;
import '../services/video_predecrypt_service.dart';
import '../services/web_launcher_service.dart';
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
  /// When server runs in isolate (Android), used to send 'close' on dispose.
  Isolate? _serverIsolate;
  SendPort? _serverIsolateSendPort;
  final FocusNode _webViewFocusNode = FocusNode();
  /// Linux fallback: HTTP URL to retry if file:// fails (Windows WebView only).
  String? _linuxHttpFallbackUrl;
  /// Linux: book opened in system browser; no in-app WebView for content.
  bool _openedExternallyOnLinux = false;
  /// Linux: last URL passed to [WebLauncherService.openWebContent] (local server or remote).
  String? _lastOpenedBookUrl;
  String? _decryptedCachePath;
  /// Extracted dir to delete on dispose when using unzip-first + decrypt-on-serve (memory optimization).
  String? _extractedDirPathForCleanup;
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
    if (!_isLoading &&
        _error == null &&
        (_useTvCursor || Platform.isWindows || (Platform.isLinux && _controller != null))) {
      _requestWebViewFocus();
    }
  }

  @override
  void dispose() {
    final server = _localServer;
    final webController = _controller;
    final isolateSendPort = _serverIsolateSendPort;
    _localServer = null;
    _serverIsolateSendPort = null;
    _serverIsolate = null;
    if (isolateSendPort != null) {
      try { isolateSendPort.send('close'); } catch (_) {}
    }
    if (server != null || webController != null) {
      Future.delayed(const Duration(milliseconds: 1200), () async {
        try {
          if (server != null) await server.close(force: true);
          await webController?.clearCache();
        } catch (_) { /* ignore */ }
      });
    }
    // Remove decrypted data to manage memory: delete decrypted zip (fallback path) and extracted dir (unzip-first path)
    if (_decryptedCachePath != null) {
      try {
        final f = File(_decryptedCachePath!);
        if (f.existsSync()) f.deleteSync();
      } catch (e) { /* ignore */ }
    }
    if (_extractedDirPathForCleanup != null) {
      try {
        final d = Directory(_extractedDirPathForCleanup!);
        if (d.existsSync()) d.deleteSync(recursive: true);
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

  /// Prevents loading all flipbook assets at once: lazy-loads images and defers off-screen content.
  /// Reduces Dart/GPU memory and GraphicBuffer failures on Android when books have 1000+ assets.
  Future<void> _injectFlipbookLazyLoad() async {
    try {
      const jsCode = r'''
        (function() {
          var style = document.createElement('style');
          style.id = 'flipbook-memory-fixes';
          style.textContent = [
            'img { max-width: 100% !important; height: auto !important; object-fit: contain !important; }',
            '.page-container img, .flipbook-page img, [class*="page"] img { max-width: 100% !important; height: auto !important; }',
            'canvas { max-width: 100% !important; height: auto !important; }'
          ].join('\n');
          if (!document.getElementById('flipbook-memory-fixes')) document.head.appendChild(style);

          [].forEach.call(document.querySelectorAll('img'), function(img) {
            img.loading = 'lazy';
            var dataSrc = img.getAttribute('data-src');
            if (dataSrc && !img.src) {
              img.setAttribute('data-src-defer', dataSrc);
              img.removeAttribute('data-src');
            }
          });

          var dataSrcDefer = document.querySelectorAll('img[data-src-defer]');
          if (dataSrcDefer.length === 0) return;
          var io = new IntersectionObserver(function(entries) {
            entries.forEach(function(entry) {
              if (!entry.isIntersecting) return;
              var img = entry.target;
              var src = img.getAttribute('data-src-defer');
              if (src) {
                img.src = src;
                img.removeAttribute('data-src-defer');
                io.unobserve(img);
              }
            });
          }, { rootMargin: '200px', threshold: 0.01 });
          dataSrcDefer.forEach(function(img) { io.observe(img); });
        })();
      ''';
      await _controller?.runJavaScript(jsCode);
    } catch (e) { /* ignore */ }
  }

  /// Keep HTML5 video inline in WebView and avoid fullscreen takeover on TV.
  Future<void> _injectVideoPlaybackFixes() async {
    try {
      const jsCode = r'''
        (function() {
          function normalizeBookUrl(u) {
            if (!u || typeof u !== 'string') return u;
            if (u.startsWith('http://') || u.startsWith('https://') || u.startsWith('blob:') || u.startsWith('data:')) return u;
            if (u.startsWith('resources/')) return '/' + u;
            return u;
          }

          function patchVideo(v) {
            if (!v) return;
            try {
              v.setAttribute('playsinline', 'true');
              v.setAttribute('webkit-playsinline', 'true');
              v.setAttribute('x5-playsinline', 'true');
              if (!v.getAttribute('preload')) v.setAttribute('preload', 'metadata');
              if (!v.hasAttribute('controls')) v.setAttribute('controls', 'controls');
              v.playsInline = true;
              v.controls = true;
            } catch (_) {}
            try {
              v.addEventListener('webkitbeginfullscreen', function(e) {
                try { e.preventDefault(); } catch (_) {}
                try { document.exitFullscreen && document.exitFullscreen(); } catch (_) {}
              });
            } catch (_) {}
            try {
              v.addEventListener('click', function() {
                try {
                  if (window.FlutterChannel && window.FlutterChannel.postMessage) {
                    window.FlutterChannel.postMessage('video_click:' + String(v.currentSrc || v.src || ''));
                  }
                } catch (_) {}
                var p = v.play && v.play();
                if (p && p.catch) p.catch(function(){});
              });
            } catch (_) {}
          }

          function openTvOverlayVideo(normalizedSrc) {
            var old = document.getElementById('tv-video-overlay');
            if (old && old.parentNode) old.parentNode.removeChild(old);
            var overlay = document.createElement('div');
            overlay.id = 'tv-video-overlay';
            overlay.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.92);z-index:2147483647;display:flex;align-items:center;justify-content:center;';
            var wrap = document.createElement('div');
            wrap.style.cssText = 'position:relative;width:92vw;height:82vh;max-width:1280px;';
            var closeBtn = document.createElement('button');
            closeBtn.textContent = 'Close';
            closeBtn.style.cssText = 'position:absolute;right:8px;top:8px;z-index:2;padding:8px 12px;background:#111;color:#fff;border:1px solid #666;border-radius:6px;';
            var v = document.createElement('video');
            v.setAttribute('playsinline', 'true');
            v.setAttribute('webkit-playsinline', 'true');
            v.controls = true;
            v.autoplay = true;
            v.preload = 'metadata';
            v.style.cssText = 'width:100%;height:100%;background:#000;object-fit:contain;';
            v.src = normalizedSrc;
            closeBtn.onclick = function() {
              try { v.pause(); } catch (_) {}
              if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
            };
            wrap.appendChild(v);
            wrap.appendChild(closeBtn);
            overlay.appendChild(wrap);
            overlay.addEventListener('click', function(e) {
              if (e.target === overlay) closeBtn.click();
            });
            document.body.appendChild(overlay);
            var p = v.play && v.play();
            if (p && p.catch) p.catch(function(){});
          }

          function shouldUseTvOverlay(normalizedSrc) {
            var lower = String(normalizedSrc || '').toLowerCase();
            return lower.indexOf('/resources/animations/') !== -1 && lower.endsWith('.mp4');
          }

          function patchOpenFancyIfPresent() {
            if (typeof window.openFancyModalVideo !== 'function') return false;
            if (window.openFancyModalVideo.__tvPatched) return true;
            var __origOpenFancyModalVideo = window.openFancyModalVideo;
            var wrapped = function(src, size) {
              var normalizedSrc = normalizeBookUrl(src);
              try {
                if (window.FlutterChannel && window.FlutterChannel.postMessage) {
                  window.FlutterChannel.postMessage('video_openFancy:' + String(src || ''));
                }
              } catch (_) {}
              try {
                if (shouldUseTvOverlay(normalizedSrc)) {
                  openTvOverlayVideo(normalizedSrc);
                  return;
                }
              } catch (_) {}
              return __origOpenFancyModalVideo.call(window, normalizedSrc, size);
            };
            wrapped.__tvPatched = true;
            window.openFancyModalVideo = wrapped;
            return true;
          }

          try {
            if (!window.__tvInlineVideoPatched) {
              window.__tvInlineVideoPatched = true;
              patchOpenFancyIfPresent();
              // Some book scripts define openFancyModalVideo late; retry briefly.
              var __tries = 0;
              var __timer = setInterval(function() {
                __tries++;
                if (patchOpenFancyIfPresent() || __tries > 20) {
                  clearInterval(__timer);
                }
              }, 500);
              if (window.HTMLVideoElement && window.HTMLVideoElement.prototype) {
                window.HTMLVideoElement.prototype.requestFullscreen = function() {
                  var p = this.play && this.play();
                  return (p && p.then) ? p : Promise.resolve();
                };
                window.HTMLVideoElement.prototype.webkitEnterFullscreen = function() {
                  var p = this.play && this.play();
                  return (p && p.then) ? p : Promise.resolve();
                };
              }
            }
          } catch (_) {}

          // Direct fallback for inline onclick="openFancyModalVideo('...')"
          // in case function wrapping misses due script timing.
          document.addEventListener('click', function(ev) {
            var el = ev.target && (ev.target.closest ? ev.target.closest('[onclick]') : null);
            if (!el) return;
            var raw = String(el.getAttribute('onclick') || '');
            if (raw.indexOf('openFancyModalVideo') === -1) return;
            var m = raw.match(/openFancyModalVideo\(\s*['"]([^'"]+)['"]/i);
            if (!m || !m[1]) return;
            var normalizedSrc = normalizeBookUrl(m[1]);
            if (!shouldUseTvOverlay(normalizedSrc)) return;
            ev.preventDefault();
            ev.stopPropagation();
            try {
              if (window.FlutterChannel && window.FlutterChannel.postMessage) {
                window.FlutterChannel.postMessage('video_openFancy:' + String(m[1]));
              }
            } catch (_) {}
            openTvOverlayVideo(normalizedSrc);
          }, true);

          document.querySelectorAll('video').forEach(patchVideo);
          document.querySelectorAll('source').forEach(function(s) {
            try { s.src = normalizeBookUrl(s.getAttribute('src')); } catch (_) {}
          });
          var mo = new MutationObserver(function(muts) {
            muts.forEach(function(m) {
              if (!m.addedNodes) return;
              Array.prototype.forEach.call(m.addedNodes, function(n) {
                if (!n) return;
                if (n.tagName && n.tagName.toLowerCase() === 'video') patchVideo(n);
                if (n.tagName && n.tagName.toLowerCase() === 'source') {
                  try { n.src = normalizeBookUrl(n.getAttribute('src')); } catch (_) {}
                }
                if (n.querySelectorAll) n.querySelectorAll('video').forEach(patchVideo);
                if (n.querySelectorAll) n.querySelectorAll('source').forEach(function(s) {
                  try { s.src = normalizeBookUrl(s.getAttribute('src')); } catch (_) {}
                });
              });
            });
          });
          mo.observe(document.documentElement || document.body, { childList: true, subtree: true });
        })();
      ''';
      await _controller?.runJavaScript(jsCode);
    } catch (_) { /* ignore */ }
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
      //await _controller?.runJavaScript(jsCode);
    } catch (e) { /* ignore */ }
  }

  /// Stops the local HTTP server (and server isolate on Android).
  Future<void> _stopLocalServer() async {
    if (_serverIsolateSendPort != null) {
      try {
        _serverIsolateSendPort!.send('close');
      } catch (_) {}
      _serverIsolateSendPort = null;
      _serverIsolate = null;
    }
    if (_localServer != null) {
      try {
        await _localServer!.close(force: true);
        _localServer = null;
      } catch (e) { /* ignore */ }
    }
  }


  /// WebView controller is created once in initState and reused for the whole screen lifetime.
  /// Never create a new controller in build() to avoid recreating the platform WebView and losing state/memory.
  void _initializeWebView() {
    if (Platform.isLinux) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
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
      return;
    }

    try {
      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..enableZoom(true)
        ..setBackgroundColor(Colors.white)
        ..addJavaScriptChannel(
          'FlutterChannel',
          onMessageReceived: (JavaScriptMessage message) {
            final msg = message.message;
            if (msg.startsWith('video_click:')) {
              final src = msg.substring('video_click:'.length);
              BookDecryptionService.logServerEvent(
                message: 'video click received',
                requestedPath: src,
              );
            } else if (msg.startsWith('video_openFancy:')) {
              final src = msg.substring('video_openFancy:'.length);
              BookDecryptionService.logServerEvent(
                message: 'openFancyModalVideo called',
                requestedPath: src,
              );
            }
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              if (mounted) setState(() {
                // Keep overlay for real loads; placeholder URLs should not flash loading state.
                if (!_isPlaceholderWebViewUrl(url)) {
                  _isLoading = true;
                }
                _error = null;
              });
            },
            onPageFinished: (String url) {
              // Placeholder navigations must not clear the Flutter overlay: on Android the WebView
              // often paints above Stack children, so users would otherwise see a white blank for the
              // whole unzip/server phase (about:blank / data: "Opening book…" finish before the book URL).
              if (_isPlaceholderWebViewUrl(url)) {
                return;
              }
              _linuxHttpFallbackUrl = null;
              if (mounted) setState(() { _isLoading = false; _loadingMessage = null; });
              _injectBookFixes();
              _injectFlipbookLazyLoad();
              _injectVideoPlaybackFixes();
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
                    _error = Platform.isAndroid
                        ? 'This book couldn’t be opened. Low memory. Close other apps, restart device. On TV, use a release build: flutter build apk.'
                        : 'This book couldn’t be opened.';
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
    final linuxNoWebView = Platform.isLinux && c == null;
    if (c == null && !linuxNoWebView) return;
    if (widget.book.contentUrl == null || widget.book.contentUrl!.isEmpty) {
      c?.loadRequest(Uri.parse('about:blank'));
      setState(() {
        _isLoading = false;
        _error = 'This book isn’t downloaded yet. Go to Sync to download it first.';
      });
      return;
    }
    final originalUrl = widget.book.contentUrl!;
    final contentUrl = _normalizeContentUrl(originalUrl);
    if (contentUrl.startsWith('assets/')) {
      if (linuxNoWebView) {
        setState(() {
          _isLoading = false;
          _error = 'This book can’t be opened in the browser.';
        });
        return;
      }
      _loadAsset(contentUrl);
    } else if (contentUrl.startsWith('file://')) {
      _loadFile(contentUrl);
    } else if (contentUrl.startsWith('http://') || contentUrl.startsWith('https://')) {
      if (linuxNoWebView) {
        unawaited(_openRemoteUrlInLinuxBrowser(contentUrl));
        return;
      }
      _controller!.loadRequest(Uri.parse(contentUrl));
    } else if (_looksLikeLocalPath(contentUrl)) {
      // Raw path (e.g. C:\path on Windows or /path) — treat as file
      final fileUrl = contentUrl.contains('://') ? contentUrl : 'file:///${contentUrl.replaceAll(r'\', '/')}';
      _loadFile(fileUrl);
    } else {
      if (linuxNoWebView) {
        setState(() {
          _isLoading = false;
          _error = 'This book can’t be opened in the browser.';
        });
        return;
      }
      _loadAsset(contentUrl);
    }
  }

  Future<void> _openRemoteUrlInLinuxBrowser(String url) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _loadingMessage = 'loading';
    });
    final ok = await WebLauncherService.openWebContent(url);
    if (!mounted) return;
    if (ok) {
      _lastOpenedBookUrl = url;
      setState(() {
        _openedExternallyOnLinux = true;
        _isLoading = false;
        _loadingMessage = null;
      });
    } else {
      setState(() {
        _isLoading = false;
        _loadingMessage = null;
        _error =
            'Could not open browser. Check that a default browser is installed.';
      });
    }
  }

  /// True if string looks like a local file path (Windows or POSIX).
  static bool _looksLikeLocalPath(String url) {
    if (url.isEmpty) return false;
    if (Platform.isWindows && url.length >= 2 && url[1] == ':') return true;
    if (url.startsWith('/') && !url.startsWith('//')) return true;
    return false;
  }

  /// Blank / interim pages while the ZIP is extracted and the local server starts.
  /// [NavigationDelegate] must not clear [_isLoading] for these or the overlay disappears too early.
  static bool _isPlaceholderWebViewUrl(String url) {
    if (url.isEmpty) return true;
    final u = url.toLowerCase();
    if (u == 'about:blank') return true;
    if (u.startsWith('data:text/html')) return true;
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

    // Show "Opening book..." in WebView so user sees it instead of black (desktop WebView draws on top of Flutter overlay).
    // On Android use minimal about:blank first to reduce heap before book load; Flutter loading overlay shows the message.
    if (mounted && _controller != null) {
      if (Platform.isAndroid) {
        _controller!.loadRequest(Uri.parse('about:blank'));
      } else if (!Platform.isLinux) {
        final openingText = 'Opening book...';
        _controller!.loadHtmlString(
          '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>'
          '<body style="display:flex;align-items:center;justify-content:center;height:100vh;margin:0;font-family:system-ui,sans-serif;color:#555;background:#fff;">'
          '<p style="font-size:1.1em;">$openingText</p></body></html>',
        );
      }
    }

    void showErr(String message, [Object? cause, StackTrace? st]) {
      if (cause != null) {
        debugPrint('[BookOpen] $message | $cause');
        if (st != null) debugPrint('[BookOpen] $st');
      } else {
        debugPrint('[BookOpen] $message');
      }
      if (mounted) setState(() { _isLoading = false; _error = message; _loadingMessage = null; });
    }

    try {
      var filePath = _fileUrlToPath(fileUrl);
      var file = File(filePath);

      // Run file check, DB lookup, and TV cursor in parallel for faster open (MSI/release)
      final results = await Future.wait([
        file.exists(),
        DatabaseService.getBookByFilePath(filePath),
        _loadTvCursorSetting(),
      ]);
      final fileExists = results[0] as bool;
      final dbBook = results[1] as Book?;
      // results[2] is _loadTvCursorSetting (no return value needed)

      if (!fileExists) {
        showErr('This book wasn’t found. It may have been moved or deleted.');
        return;
      }
      if (!ZipHandler.isZipFile(filePath)) {
        showErr('Unsupported book format. Only ZIP books are supported.');
        return;
      }
      final encBookId = dbBook?.encBookId ?? widget.book.encBookId;
      final encKeyB64 = dbBook?.encKeyB64 ?? widget.book.encKeyB64;
      final encNonceB64 = dbBook?.encNonceB64 ?? widget.book.encNonceB64;

      // Encrypted: unzip first (zip has encrypted chapters/assets), then decrypt each file when opening.
      final hasEncMeta = (encBookId != null && encBookId.isNotEmpty) &&
          (encKeyB64 != null && encKeyB64.isNotEmpty) &&
          (encNonceB64 != null && encNonceB64.isNotEmpty);
      Uint8List? contentKey;
      bool unzipFirstSucceeded = false;

      if (hasEncMeta) {
        if (mounted) setState(() { _loadingMessage = 'unlocking'; });
        await Future.delayed(Duration.zero);
        final zipPath = filePath;
        debugPrint('[BookOpen] encrypted book: unzip-first try zip=$zipPath');
        try {
          // Extract to disk only; never load the entire ZIP into memory (avoids OOM with large flipbooks).
          final extractDirPath = await ZipHandler.getExtractDirPath(zipPath);
          // On Android run unzip in background isolate to avoid main-thread heap pressure and skipped frames.
          if (Platform.isAndroid) {
            final _ = await compute(extractZipToDirBackground, (zipPath, extractDirPath));
          } else {
            await ZipHandler.extractZipToDir(zipPath, extractDirPath);
          }
          final indexHtml = await ZipHandler.findIndexHtml(extractDirPath);
          if (indexHtml != null) {
            unzipFirstSucceeded = true;
            _extractedDirPathForCleanup = extractDirPath;
            debugPrint('[BookOpen] unzip-first ok index=$indexHtml');
            contentKey = await BookDecryptionService.getContentKey(
              bookId: encBookId!,
              keyEncB64: encKeyB64!,
              keyNonceB64: encNonceB64!,
            );
          } else {
            debugPrint(
              '[BookOpen] unzip-first: no index.html under extract dir (will try whole-file decrypt): $extractDirPath',
            );
          }
        } catch (e, st) {
          // Zip invalid or no index (e.g. whole file encrypted): fall back to decrypt whole zip then unzip
          debugPrint('[BookOpen] unzip-first failed (will try whole-file decrypt if needed): $e\n$st');
        }
        if (!unzipFirstSucceeded) {
          try {
            final result = await decryptBookFileIfNeeded(
              encryptedFilePath: zipPath,
              encBookId: encBookId,
              encKeyB64: encKeyB64,
              encNonceB64: encNonceB64,
            );
            filePath = result.pathToUse;
            _decryptedCachePath = result.pathToUse;
            file = File(filePath);
          } catch (e, st) {
            final err = e.toString();
            final tooLarge = err.contains('too large') || err.contains('Maximum supported');
            showErr(
              tooLarge
                  ? 'This book file is too large to decrypt on this device. Try a smaller book or a device with more memory.'
                  : 'This book couldn’t be opened. It may be damaged or in the wrong format.',
              e,
              st,
            );
            return;
          }
        }
      }

      Directory bookDirectory;
      String? indexHtmlPath;

      if (unzipFirstSucceeded && _extractedDirPathForCleanup != null) {
        bookDirectory = Directory(_extractedDirPathForCleanup!);
        indexHtmlPath = await ZipHandler.findIndexHtml(bookDirectory.path);
        if (indexHtmlPath == null) {
          showErr('This book couldn’t be opened. No index found.');
          return;
        }
      } else {
        if (mounted) setState(() { _loadingMessage = 'preparing'; });
        ({String path, bool wasExtracted}) processed;
        try {
          processed = await ZipHandler.processBookFileOffMain(filePath);
          filePath = processed.path;
        } on FormatException catch (e, st) {
          showErr('Incorrect format.', e, st);
          return;
        }
        file = File(filePath);
        final isFile = await file.exists();
        final dir = Directory(filePath);
        final isDirectory = await dir.exists();
        if (isFile) {
          bookDirectory = file.parent;
          indexHtmlPath = filePath;
        } else if (isDirectory) {
          indexHtmlPath = await ZipHandler.findIndexHtml(filePath);
          if (indexHtmlPath == null) {
            showErr('No index.html found in book.');
            return;
          }
          bookDirectory = dir;
        } else {
          showErr('This book couldn’t be opened.');
          return;
        }
      }

      if (contentKey != null && !Platform.isAndroid) {
        // Skip verification on Android to avoid any read+decrypt on main isolate (reduces "Exhausted heap space").
        if (mounted) setState(() { _loadingMessage = 'verifying'; });
        await _verifyDecryptionBeforeLoad(
          bookDirectory: bookDirectory,
          indexHtmlPath: indexHtmlPath!,
          contentKey: contentKey,
        );
        // Do not block loading: verification is best-effort; decrypt-on-serve will try per file.
      }

      if (mounted) setState(() { _loadingMessage = 'loading'; });
      debugPrint('[BookOpen] starting local server bookDir=${bookDirectory.path} encrypted=${contentKey != null}');
      await _startLocalServer(bookDirectory, contentKey: contentKey);
      debugPrint('[BookOpen] local server listening on port $_serverPort');
      if (Platform.isAndroid && contentKey != null) {
        unawaited(_predecryptVideosInBackground(bookDirectory, contentKey));
      }
      final relativePath = path.relative(indexHtmlPath, from: bookDirectory.path);
      final urlPath = relativePath.replaceAll('\\', '/');
      final httpUrl = 'http://127.0.0.1:$_serverPort/$urlPath';

      if (Platform.isLinux) {
        _lastOpenedBookUrl = httpUrl;
        final launched = await WebLauncherService.openWebContent(httpUrl);
        if (!mounted) return;
        if (!launched) {
          await _stopLocalServer();
          setState(() {
            _isLoading = false;
            _error =
                'Could not open browser. Install a default browser or try again.';
            _loadingMessage = null;
          });
          return;
        }
        setState(() {
          _openedExternallyOnLinux = true;
          _isLoading = false;
          _loadingMessage = null;
        });
        return;
      }

      // Book is always loaded from a URL (local HTTP or file://), never from in-memory HTML.
      // This keeps the flipbook and its 1000+ assets streamed from disk/server instead of buffered in Dart.
      String bookUrl;
      if (contentKey != null) {
        // Encrypted entries: must use HTTP so every request is decrypted on serve
        _linuxHttpFallbackUrl = null;
        bookUrl = httpUrl;
      } else if (Platform.isWindows) {
        // Desktop: try file:// first so WebView doesn't hit localhost restrictions. Fallback to HTTP if it fails.
        bookUrl = Uri.file(indexHtmlPath).toString();
        _linuxHttpFallbackUrl = httpUrl;
      } else {
        _linuxHttpFallbackUrl = null;
        bookUrl = httpUrl;
      }

      if (Platform.isWindows) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          _controller?.loadRequest(Uri.parse(bookUrl));
          // If file:// fails, onWebResourceError will retry with HTTP fallback
        });
      } else {
        // Android/Android TV: two-phase load to avoid "Exhausted heap space" and blank screen.
        // 1) Clear cache, wait, load a minimal page so WebView/Chromium finish startup (codec probe, EGL).
        // 2) Wait longer, then load the book URL so we don't hit OOM when Chromium and Dart are both under pressure.
        if (mounted) setState(() => _isLoading = true);
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            await _controller?.clearCache();
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 1500));
          if (!mounted) return;
          for (int i = 0; i < 3; i++) {
            await Future.delayed(Duration.zero);
            if (!mounted) return;
          }
          try {
            const loadingDataUrl = "data:text/html;charset=utf-8,"
                "%3C!DOCTYPE html%3E%3Chtml%3E%3Cbody style='margin:0;display:flex;align-items:center;justify-content:center;"
                "height:100vh;font-family:system-ui;color:%23666;'%3EOpening book...%3C/body%3E%3C/html%3E";
            _controller?.loadRequest(Uri.parse(loadingDataUrl));
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 3500));
          if (!mounted) return;
          for (int i = 0; i < 5; i++) {
            await Future.delayed(Duration.zero);
            if (!mounted) return;
          }
          try {
            _controller?.loadRequest(Uri.parse(bookUrl));
          } catch (e, st) {
            debugPrint('[BookOpen] WebView loadRequest failed: $e\n$st');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _error = 'This book couldn’t be opened.';
              });
            }
          }
        });
      }
    } catch (e, st) {
      debugPrint('[BookOpen] open book failed: $e\n$st');
      await _stopLocalServer();
      if (mounted) {
        final errorStr = e.toString().toLowerCase();
        final isTooLarge = errorStr.contains('too large') || errorStr.contains('maximum supported');
        final isFormatOrDecrypt = errorStr.contains('format') ||
            errorStr.contains('invalid zip') ||
            errorStr.contains('corrupt') ||
            errorStr.contains('decryption') ||
            errorStr.contains('secretbox') ||
            errorStr.contains('authentication') ||
            errorStr.contains('wrong mac') ||
            errorStr.contains('index.html');
        final String friendlyMessage = isTooLarge
            ? 'This book file is too large to decrypt on this device. Try a smaller book or a device with more memory.'
            : isFormatOrDecrypt
                ? 'This book couldn’t be opened. It may be damaged or in the wrong format.'
                : 'This book couldn’t be opened.';
        setState(() { _isLoading = false; _error = friendlyMessage; _loadingMessage = null; });
      }
    }
  }

  /// Encrypted path check uses manifest.json when present (see [isEncryptedPath] in book_manifest.dart); else paths under resources/ are encrypted.

  /// Max size (bytes) of the file used for pre-load verification on Android (avoid main-isolate OOM).
  static const int _kVerifyMaxFileBytesAndroid = 128 * 1024; // 128 KB

  /// Verifies decryption works before loading (decrypts one file under resources/; only resources folder is encrypted).
  /// On Android uses only a small file (<= 128 KB) to avoid "Exhausted heap space" on main isolate.
  Future<bool> _verifyDecryptionBeforeLoad({
    required Directory bookDirectory,
    required String indexHtmlPath,
    required Uint8List contentKey,
  }) async {
    try {
      // Only resources/ content is encrypted: find one file under resources/ to verify
      final resourcesDir = Directory(path.join(bookDirectory.path, 'resources'));
      if (!await resourcesDir.exists()) return true; // no resources, nothing to verify
      File? firstUnderResources;
      await for (final entity in resourcesDir.list(recursive: true)) {
        if (entity is File) {
          if (Platform.isAndroid) {
            final len = await entity.length();
            if (len > _kVerifyMaxFileBytesAndroid) continue; // skip large files on Android
          }
          firstUnderResources = entity;
          break;
        }
      }
      if (firstUnderResources == null) return true;
      final relativePath = path.relative(firstUnderResources.path, from: bookDirectory.path).replaceAll('\\', '/');
      final bytes = await firstUnderResources.readAsBytes();
      Uint8List? decrypted;
      try {
        decrypted = await BookDecryptionService.decryptFileBytes(
          encryptedBytes: bytes,
          contentKey: contentKey,
          requestedPath: relativePath,
          aad: [],
        );
      } catch (_) {
        try {
          decrypted = await BookDecryptionService.decryptFileBytes(
            encryptedBytes: bytes,
            contentKey: contentKey,
            requestedPath: relativePath,
            aad: utf8.encode(relativePath),
          );
        } catch (_) {
          return false;
        }
      }
      if (decrypted != null && decrypted.length > 0) {
        BookDecryptionService.logDecryptSuccess(path: relativePath, size: decrypted.length);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Logs each server request to decrypt_log.txt (path, status, note) to debug blank chapter content.
  static void _logServerRequest(String requestedPath, int status, String note) {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final logFile = File(path.join(exeDir.path, 'decrypt_log.txt'));
      final line = '${DateTime.now().toIso8601String()} request: $requestedPath -> $status $note\n';
      logFile.writeAsStringSync(line, mode: FileMode.append);
    } catch (_) {}
  }

  /// Logs whether decryption worked for a page (so you can see "DECRYPTION ON PAGE: OK/FAIL" in decrypt_log.txt).
  static void _logDecryptionOnPage(bool success, String requestedPath, {int? sizeBytes, Object? error}) {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final logFile = File(path.join(exeDir.path, 'decrypt_log.txt'));
      final status = success ? 'OK' : 'FAIL';
      final sizeStr = sizeBytes != null ? ' ($sizeBytes bytes)' : '';
      final errorStr = error != null ? ' error: $error' : '';
      final line = '${DateTime.now().toIso8601String()} DECRYPTION ON PAGE: $status $requestedPath$sizeStr$errorStr\n';
      logFile.writeAsStringSync(line, mode: FileMode.append);
    } catch (_) {}
  }

  /// In debug mode, writes decrypted page/asset to debug_decrypted_pages/ for inspection.
  static Future<void> _debugSaveDecryptedPage(String requestedPath, Uint8List bytes) async {
    if (!kDebugMode) return;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final safePath = requestedPath.replaceAll('..', '_').replaceAll('\\', '/').trimLeft();
      final dir = Directory(path.join(exeDir.path, 'debug_decrypted_pages'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final outPath = path.join(dir.path, safePath);
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(bytes);
    } catch (_) {}
  }

  /// Logs book directory structure at server start so we can see where chapter/webp files live.
  static Future<void> _logBookDirectoryStructure(Directory bookDirectory) async {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final logFile = File(path.join(exeDir.path, 'decrypt_log.txt'));
      final buffer = StringBuffer()
        ..writeln('---')
        ..writeln('${DateTime.now().toIso8601String()} book dir: ${bookDirectory.path}')
        ..writeln('listing (first 100 entries):');
      var count = 0;
      await for (final entity in bookDirectory.list(recursive: true)) {
        if (count >= 100) break;
        final rel = path.relative(entity.path, from: bookDirectory.path).replaceAll('\\', '/');
        buffer.writeln('  $rel');
        count++;
      }
      buffer.writeln('---');
      await logFile.writeAsString(buffer.toString(), mode: FileMode.append);
    } catch (_) {}
  }

  /// Tries alternate path patterns for chapter/webp (e.g. page/1.webp -> pages/1.webp, or find by filename).
  static Future<String?> _resolveChapterPathFallback(Directory bookDirectory, String requestedPath) async {
    final fileName = path.basename(requestedPath);
    if (fileName.isEmpty) return null;
    final alternates = <String>[
      requestedPath,
      requestedPath.replaceFirst('page/', 'pages/'),
      requestedPath.replaceFirst('pages/', 'page/'),
      requestedPath.replaceFirst('page/', 'chapters/'),
      requestedPath.replaceFirst('chapters/', 'page/'),
      requestedPath.replaceFirst('chapters/', 'pages/'),
      'pages/$fileName',
      'page/$fileName',
      'chapters/$fileName',
      fileName,
    ];
    for (final alt in alternates) {
      if (alt == requestedPath) continue;
      final full = path.join(bookDirectory.path, alt);
      final f = File(full);
      if (await f.exists()) return full;
    }
    try {
      await for (final entity in bookDirectory.list(recursive: true)) {
        if (entity is File && path.basename(entity.path).toLowerCase() == fileName.toLowerCase()) {
          return entity.path;
        }
      }
    } catch (_) {}
    return null;
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

  /// Starts a local HTTP server to serve book files.
  /// On Android the server runs in a separate isolate so the main isolate never holds decrypted file bytes (avoids "Exhausted heap space").
  Future<void> _startLocalServer(Directory bookDirectory, {Uint8List? contentKey}) async {
    await _stopLocalServer();

    if (Platform.isAndroid) {
      _serverPort = 8080;
      final completer = Completer<void>();
      final receivePort = ReceivePort();
      receivePort.listen((message) {
        if (message is SendPort) {
          _serverIsolateSendPort = message;
          _serverIsolateSendPort!.send([bookDirectory.path, contentKey, _serverPort]);
        } else if (message == 'ready') {
          if (!completer.isCompleted) completer.complete();
        } else if (message is List && message.length >= 2 && message[0] == 'error') {
          if (!completer.isCompleted) completer.completeError(Exception(message[1].toString()));
        }
      });
      _serverIsolate = await Isolate.spawn(isolate_runner.bookServerIsolateEntry, receivePort.sendPort);
      try {
        await completer.future;
      } finally {
        receivePort.close();
      }
      return;
    }

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
    await _logBookDirectoryStructure(bookDirectory);

    // Use manifest.json for encrypted paths when present; else fall back to resources/
    final serverEncryptedPaths = await loadEncryptedPathsFromManifest(bookDirectory.path);

    String? cachedDecryptedPath;
    Uint8List? cachedDecryptedBytes;
    final Set<String> first206VideoLogged = <String>{};

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
        if (!await file.exists()) {
          final fallback = await _resolveChapterPathFallback(bookDirectory, requestedPath);
          if (fallback != null) {
            filePath = fallback;
            file = File(filePath);
          }
        }

        if (!await file.exists()) {
          _logServerRequest(requestedPath, 404, 'not found');
          request.response
            ..statusCode = HttpStatus.notFound
            ..headers.set('Content-Type', 'text/plain; charset=utf-8')
            ..write('File not found: ${request.uri.path}')
            ..close();
          return;
        }

        if (await file.exists()) {
          var ext = path.extension(filePath).toLowerCase();
          if (ext.isEmpty && requestedPath.contains('.')) {
            ext = '.${requestedPath.split('.').last.toLowerCase()}';
          }
          final String mimeStr = _mimeTypeForExtension(ext);
          final pathForDecrypt = path.relative(filePath, from: bookDirectory.path).replaceAll('\\', '/');
          final predecryptedPath = _predecryptedVideoPath(bookDirectory.path, pathForDecrypt);
          var servedFromPredecrypted = false;
          if (_isVideoPath(pathForDecrypt)) {
            final pre = File(predecryptedPath);
            if (await pre.exists()) {
              file = pre;
              filePath = predecryptedPath;
              servedFromPredecrypted = true;
            }
          }
          final isEncrypted = contentKey != null &&
              !servedFromPredecrypted &&
              isEncryptedPath(pathForDecrypt, serverEncryptedPaths);
          final fileLength = await file.length();
          final range = _parseByteRange(request.headers.value(HttpHeaders.rangeHeader), fileLength);

          // Android: reject encrypted files that exceed per-path max size before reading (avoid OOM).
          final maxAllowed = BookDecryptionService.maxDecryptBytesForPath(pathForDecrypt);
          if (isEncrypted && fileLength > maxAllowed) {
            _logServerRequest(requestedPath, 413, 'file too large for decrypt (max $maxAllowed)');
            BookDecryptionService.logDecryptBlocked(
              requestedPath: pathForDecrypt,
              fileSizeBytes: fileLength,
              maxAllowedBytes: maxAllowed,
            );
            request.response
              ..statusCode = 413
              ..headers.set('Content-Type', 'text/plain; charset=utf-8')
              ..write('File too large to decrypt on this device.')
              ..close();
            return;
          }

          if (isEncrypted) {
            if (_isVideoPath(pathForDecrypt)) {
              final cachedVideoFile = File(_predecryptedVideoPath(bookDirectory.path, pathForDecrypt));
              if (!await cachedVideoFile.exists()) {
                BookDecryptionService.logServerEvent(
                  message: 'video decrypt start',
                  requestedPath: pathForDecrypt,
                );
                final encryptedBytes = await file.readAsBytes();
                Uint8List decryptedVideoBytes;
                try {
                  decryptedVideoBytes = await BookDecryptionService.decryptFileBytesWithOptionalAad(
                    encryptedBytes: encryptedBytes,
                    contentKey: contentKey!,
                    requestedPath: pathForDecrypt,
                  );
                } catch (e) {
                  final isMacError = e.toString().toLowerCase().contains('mac') ||
                      e.toString().toLowerCase().contains('secretboxauthentication');
                  if (!isMacError) {
                    _logServerRequest(requestedPath, 500, 'video decrypt failed');
                    request.response
                      ..statusCode = HttpStatus.internalServerError
                      ..headers.set('Content-Type', 'text/plain; charset=utf-8')
                      ..write('Decryption failed: $e')
                      ..close();
                    return;
                  }
                  decryptedVideoBytes = encryptedBytes;
                }
                await cachedVideoFile.parent.create(recursive: true);
                await cachedVideoFile.writeAsBytes(decryptedVideoBytes, flush: false);
                BookDecryptionService.logServerEvent(
                  message: 'video decrypt end',
                  requestedPath: pathForDecrypt,
                  sizeBytes: decryptedVideoBytes.length,
                );
              }

              final cachedLength = await cachedVideoFile.length();
              final videoRange = _parseByteRange(
                request.headers.value(HttpHeaders.rangeHeader),
                cachedLength,
              );
              final response = request.response;
              response
                ..headers.set('Content-Type', mimeStr)
                ..headers.contentType = ContentType.parse(mimeStr)
                ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
              if (videoRange != null) {
                final start = videoRange.start;
                final end = videoRange.end;
                if (!first206VideoLogged.contains(pathForDecrypt)) {
                  first206VideoLogged.add(pathForDecrypt);
                  BookDecryptionService.logServerEvent(
                    message: 'video first 206 response sent',
                    requestedPath: pathForDecrypt,
                    details: 'range=$start-$end',
                  );
                }
                _logServerRequest(requestedPath, 206, 'video cached partial');
                response
                  ..statusCode = HttpStatus.partialContent
                  ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$cachedLength')
                  ..headers.contentLength = end - start + 1;
                await for (final chunk in cachedVideoFile.openRead(start, end + 1)) {
                  response.add(chunk);
                }
                await response.close();
              } else {
                _logServerRequest(requestedPath, 200, 'video cached');
                response.headers.contentLength = cachedLength;
                await for (final chunk in cachedVideoFile.openRead()) {
                  response.add(chunk);
                }
                await response.close();
              }
              return;
            }

            Uint8List? toServe;
            var servedPlainFallback = false;
            if (cachedDecryptedPath == pathForDecrypt && cachedDecryptedBytes != null) {
              toServe = cachedDecryptedBytes!;
            } else {
              // Encrypted: read → decrypt → serve (single buffer at a time for Android).
              final encryptedBytes = await file.readAsBytes();
              try {
                toServe = await BookDecryptionService.decryptFileBytesWithOptionalAad(
                  encryptedBytes: encryptedBytes,
                  contentKey: contentKey!,
                  requestedPath: pathForDecrypt,
                );
                _logDecryptionOnPage(true, requestedPath, sizeBytes: toServe.length);
                if (!Platform.isAndroid) await _debugSaveDecryptedPage(requestedPath, toServe);
                // Cache decrypted bytes for repeated range requests (especially mp4 playback).
                final lower = pathForDecrypt.toLowerCase();
                final shouldCache = lower.endsWith('.mp4') ||
                    lower.endsWith('.webm') ||
                    lower.endsWith('.css') ||
                    lower.endsWith('.js') ||
                    lower.endsWith('.html');
                if (shouldCache && toServe.length <= 8 * 1024 * 1024) {
                  cachedDecryptedPath = pathForDecrypt;
                  cachedDecryptedBytes = toServe;
                }
              } catch (e) {
                _logDecryptionOnPage(false, requestedPath, error: e);
                BookDecryptionService.logDecryptFailure(
                  requestedPath: requestedPath,
                  fileSizeBytes: encryptedBytes.length,
                  error: e,
                );
                final isMacError = e.toString().toLowerCase().contains('mac') ||
                    e.toString().toLowerCase().contains('secretboxauthentication');
                if (!isMacError) {
                  _logServerRequest(requestedPath, 500, 'decrypt failed');
                  request.response
                    ..statusCode = HttpStatus.internalServerError
                    ..headers.set('Content-Type', 'text/plain; charset=utf-8')
                    ..write('Decryption failed: $e')
                    ..close();
                  return;
                }
                toServe = encryptedBytes;
                servedPlainFallback = true;
              }
            }
            final response = request.response;
            response.headers.set('Content-Type', mimeStr);
            response.headers.contentType = ContentType.parse(mimeStr);
            response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
            final contentLength = toServe.length;
            final decryptedRange = _parseByteRange(
              request.headers.value(HttpHeaders.rangeHeader),
              contentLength,
            );
            if (decryptedRange != null) {
              final start = decryptedRange.start;
              final end = decryptedRange.end;
              final partial = toServe.sublist(start, end + 1);
              _logServerRequest(requestedPath, 206, servedPlainFallback ? 'plain partial' : 'decrypted partial');
              response
                ..statusCode = HttpStatus.partialContent
                ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$contentLength')
                ..headers.contentLength = partial.length
                ..add(partial);
              await response.close();
            } else {
              _logServerRequest(requestedPath, 200, servedPlainFallback ? 'plain (decrypt failed)' : 'decrypted');
              response
                ..headers.contentLength = contentLength
                ..add(toServe);
              await response.close();
            }
          } else {
            // Plain file: stream in chunks to avoid loading entire file into memory (Android OOM).
            final response = request.response;
            response.headers.set('Content-Type', mimeStr);
            response.headers.contentType = ContentType.parse(mimeStr);
            response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
            if (range != null) {
              final start = range.start;
              final end = range.end;
              _logServerRequest(requestedPath, 206, 'partial');
              response
                ..statusCode = HttpStatus.partialContent
                ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$fileLength')
                ..headers.contentLength = end - start + 1;
              await for (final chunk in file.openRead(start, end + 1)) {
                response.add(chunk);
              }
              await response.close();
            } else {
              _logServerRequest(requestedPath, 200, 'ok');
              response.headers.contentLength = fileLength;
              await for (final chunk in file.openRead()) {
                response.add(chunk);
              }
              await response.close();
            }
          }
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

  ({int start, int end})? _parseByteRange(String? header, int totalLength) {
    if (header == null || !header.startsWith('bytes=')) return null;
    final value = header.substring(6).trim();
    if (value.isEmpty || value.contains(',')) return null;
    final parts = value.split('-');
    if (parts.length != 2) return null;
    final startStr = parts[0].trim();
    final endStr = parts[1].trim();
    if (startStr.isEmpty) {
      final suffix = int.tryParse(endStr);
      if (suffix == null || suffix <= 0) return null;
      final start = (totalLength - suffix).clamp(0, totalLength - 1);
      return (start: start, end: totalLength - 1);
    }
    final start = int.tryParse(startStr);
    if (start == null || start < 0 || start >= totalLength) return null;
    final end = endStr.isEmpty ? totalLength - 1 : (int.tryParse(endStr) ?? totalLength - 1);
    if (end < start) return null;
    final normalizedEnd = end >= totalLength ? totalLength - 1 : end;
    return (start: start, end: normalizedEnd);
  }

  static bool _isVideoPath(String relativePath) {
    final lower = relativePath.toLowerCase();
    return lower.endsWith('.mp4') || lower.endsWith('.webm');
  }

  static String _predecryptedVideoPath(String bookDirPath, String relativePath) {
    return path.join(bookDirPath, '.decrypted_video_cache', relativePath);
  }

  Future<void> _predecryptVideosInBackground(Directory bookDirectory, Uint8List contentKey) async {
    try {
      final encryptedPaths = await loadEncryptedPathsFromManifest(bookDirectory.path);
      final outDirPath = path.join(bookDirectory.path, '.decrypted_video_cache');
      final params = VideoPredecryptParams(
        bookDirPath: bookDirectory.path,
        outputDirPath: outDirPath,
        contentKey: contentKey,
        encryptedPathsLower: encryptedPaths?.toList(),
      );
      unawaited(
        compute(predecryptVideoFilesBackground, params).catchError((_) => 0),
      );
    } catch (_) {
      // best effort
    }
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
    if (_controller != null) {
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
    } else {
      await Future.delayed(const Duration(milliseconds: 100));
    }
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
                        if (widget.book.contentUrl == null ||
                            widget.book.contentUrl!.isEmpty) {
                          Navigator.maybePop(context);
                          return;
                        }
                        setState(() {
                          _error = null;
                          _openedExternallyOnLinux = false;
                          _lastOpenedBookUrl = null;
                        });
                        if (Platform.isLinux && _controller == null) {
                          setState(() {
                            _isLoading = true;
                            _loadingMessage = 'opening';
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _startLoadingContent();
                          });
                        } else {
                          _controller?.reload();
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
            else if (_openedExternallyOnLinux && _error == null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.open_in_browser,
                          size: 64, color: Colors.grey.shade700),
                      const SizedBox(height: 20),
                      Text(
                        'Book opened in your browser',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Keep this app open while you read. Closing this screen stops the local server and the book tab may stop loading.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey.shade700,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      if (_lastOpenedBookUrl != null) ...[
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final url = _lastOpenedBookUrl;
                            if (url == null) return;
                            final ok =
                                await WebLauncherService.openWebContent(url);
                            if (!mounted) return;
                            if (!ok) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Could not open browser again.'),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Open in browser again'),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else if (_controller != null)
              // Reuse same WebView instance (controller created once in initState); do not recreate on build().
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

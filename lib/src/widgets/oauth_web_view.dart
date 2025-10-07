// ignore_for_file: use_build_context_synchronously

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/oauth_provider.dart';
import '../services/oauth_service.dart';

class OAuthWebView extends StatefulWidget {
  final OAuthProvider provider;
  final Widget? loadingWidget;
  final Color? backgroundColor;
  final void Function()? onInitialize;
  final bool
      debugDisableRedirectHandling; // TEST ONLY - prevents redirect handling to see error page

  const OAuthWebView({
    super.key,
    required this.provider,
    this.loadingWidget,
    this.backgroundColor = Colors.white, // Default to white instead of null
    this.onInitialize,
    this.debugDisableRedirectHandling =
        false, // Default: handle redirects normally
  });

  @override
  State<OAuthWebView> createState() => _OAuthWebViewState();
}

class _OAuthWebViewState extends State<OAuthWebView>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  bool _firstLoad = true;
  String? _authorizationUrl;
  String? _userAgent;
  late final String _debugTag;
  InAppWebViewController? _webViewController;
  bool _isDisposed = false;
  bool _isHandlingRedirect = false;
  bool _errorPageShown = false; // Prevent infinite error loop

  static const int _maxInitializationAttempts = 3;
  static const Duration _initializationRetryDelay = Duration(seconds: 2);
  int _initializationAttempts = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _debugTag = 'OAuthWebView[${widget.provider.name}]';
    debugPrint('$_debugTag - Initializing');
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _disposeWebView();
    } else if (state == AppLifecycleState.resumed &&
        !_isDisposed &&
        _webViewController == null) {
      _retryAuthorization();
    }
  }

  Future<void> _disposeWebView() async {
    if (_webViewController != null) {
      _webViewController?.dispose();
      _webViewController = null;
    }
  }

  Future<void> _initialize() async {
    if (_isDisposed) return;

    try {
      await Future.wait([
        _getUserAgent(),
        _loadAuthorizationUrl(),
      ]);
      _initializationAttempts = 0;
      if (mounted && !_isDisposed) {
        setState(() {
          _errorPageShown = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('$_debugTag - Initialization failed: $e');
      debugPrint('$_debugTag - Stack trace: $stackTrace');
      _initializationAttempts += 1;

      if (_initializationAttempts >= _maxInitializationAttempts) {
        debugPrint(
            '$_debugTag - Initialization reached max retry attempts, showing error UI');
        if (mounted && !_isDisposed) {
          setState(() {
            _errorPageShown = true;
            _isLoading = false;
          });
        }
        return;
      }

      await Future.delayed(_initializationRetryDelay);
      if (!_isDisposed) {
        await _initialize();
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _webViewController?.dispose();
    _webViewController = null;
    super.dispose();
  }

  Future<bool> _tryHandleRedirect(
    String url, {
    InAppWebViewController? controller,
    bool loadBlankPage = true,
  }) async {
    if (!_shouldHandleRedirect(url)) {
      return false;
    }

    debugPrint('$_debugTag - 🎯 Starting redirect handling');
    debugPrint('$_debugTag - URL: ${_maskSensitiveUrl(url)}');

    _isHandlingRedirect = true;

    if (controller != null) {
      try {
        debugPrint('$_debugTag - 🛑 Stopping WebView loading');
        await controller.stopLoading();
      } catch (e) {
        debugPrint('$_debugTag - ⚠️ Failed to stop loading: $e');
      }

      if (loadBlankPage) {
        try {
          debugPrint('$_debugTag - 📄 Loading blank page');
          await controller.loadData(
            data: _getBlankPageHtml(),
            mimeType: 'text/html',
            encoding: 'utf-8',
          );
        } catch (e) {
          debugPrint('$_debugTag - ⚠️ Failed to load blank page: $e');
        }
      }
    }

    if (mounted && !_isDisposed) {
      setState(() {
        _isLoading = true;
        _errorPageShown = false;
      });
    }

    try {
      debugPrint('$_debugTag - 🔄 Processing OAuth redirect...');
      final result = await OAuthService.handleRedirect(url, widget.provider);
      debugPrint('$_debugTag - ✅ OAuth redirect successful');
      if (!_isDisposed && mounted) {
        await Navigator.of(context).maybePop(result);
      }
    } catch (e, stackTrace) {
      debugPrint('$_debugTag - ❌ ERROR: OAuth redirect failed: $e');
      debugPrint('$_debugTag - Stack trace: $stackTrace');
      if (!_isDisposed && mounted) {
        await Navigator.of(context).maybePop();
      }
    } finally {
      if (!_isDisposed) {
        _isHandlingRedirect = false;
        debugPrint('$_debugTag - 🏁 Redirect handling completed');
      }
    }

    return true;
  }

  bool _shouldHandleRedirect(String url) {
    if (_isDisposed ||
        _isHandlingRedirect ||
        widget.debugDisableRedirectHandling) {
      return false;
    }

    return _isRedirectUrl(url);
  }

  Future<void> _retryAuthorization() async {
    if (_isDisposed) {
      return;
    }

    _initializationAttempts = 0;

    if (mounted) {
      setState(() {
        _errorPageShown = false;
        _isLoading = true;
      });
    }
    await _initialize();
  }

  Future<void> _getUserAgent() async {
    if (_isDisposed) return;

    try {
      final deviceInfo = DeviceInfoPlugin();
      final packageInfo = await PackageInfo.fromPlatform();

      final appVersion = packageInfo.version;

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        _userAgent =
            'Mozilla/5.0 (Linux; Android ${androidInfo.version.release}; ${androidInfo.model}) '
            'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/Unknown Mobile Safari/537.36 '
            '${packageInfo.appName}/$appVersion';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _userAgent =
            'Mozilla/5.0 (${iosInfo.model}; CPU iPhone OS ${iosInfo.systemVersion.replaceAll('.', '_')} like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1 '
            '${packageInfo.appName}/$appVersion';
      } else {
        _userAgent =
            'Mozilla/5.0 (Unknown) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';
      }

      if (!_isDisposed && mounted) setState(() {});
    } catch (e, stackTrace) {
      debugPrint('$_debugTag - Error getting user agent: $e');
      debugPrint('$_debugTag - Stack trace: $stackTrace');
      _userAgent =
          'Mozilla/5.0 (Unknown) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Mobile Safari/537.36';
    }
  }

  Future<void> _loadAuthorizationUrl() async {
    if (_isDisposed) return;

    try {
      final url = await OAuthService.getAuthorizationUrl(widget.provider);
      if (!_isDisposed && mounted) {
        setState(() => _authorizationUrl = url);
        if (_webViewController != null) {
          await _webViewController!.loadUrl(
            urlRequest: URLRequest(url: WebUri(url)),
          );
        }
      }
    } catch (e, stackTrace) {
      debugPrint('$_debugTag - Error loading authorization URL: $e');
      debugPrint('$_debugTag - Stack trace: $stackTrace');
      if (!_isDisposed) {
        await Future.delayed(_initializationRetryDelay);
        if (!_isDisposed && mounted) {
          await _loadAuthorizationUrl();
        }
      }
    }
  }

  String _maskSensitiveUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final maskedParams = uri.queryParameters.map((key, value) {
        if (['client_id', 'state', 'code_verifier', 'code_challenge']
            .contains(key)) {
          return MapEntry(key, '***');
        }
        return MapEntry(key, value);
      });
      return uri.replace(queryParameters: maskedParams).toString();
    } catch (e) {
      return 'Invalid URL';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDisposed) return const SizedBox();

    // Get the background color with a fallback to white
    final backgroundColor = widget.backgroundColor ?? Colors.white;

    if (_authorizationUrl == null || _userAgent == null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: widget.loadingWidget ?? const CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_authorizationUrl!)),
            initialSettings: InAppWebViewSettings(
              cacheEnabled: false,
              javaScriptEnabled: true,
              userAgent: _userAgent,
              defaultTextEncodingName: 'UTF-8',
              // Disable default error page to prevent infinite loops
              disableDefaultErrorPage: true,
              // Additional settings to prevent default error pages
              supportZoom: false,
              displayZoomControls: false,
              clearCache: true,
              clearSessionCache: true,
              // Force disable error page rendering
              useShouldInterceptRequest: true,
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;

              controller.addJavaScriptHandler(
                handlerName: 'FlutterChannel',
                callback: (args) {},
              );
            },
            onLoadStart: (controller, url) async {
              if (_isDisposed || !mounted) return;

              final urlString = url?.toString() ?? '';
              debugPrint(
                  '$_debugTag - 🌐 [onLoadStart] URL: ${_maskSensitiveUrl(urlString)}');

              final handled = await _tryHandleRedirect(
                urlString,
                controller: controller,
              );

              if (handled) {
                debugPrint(
                    '$_debugTag - 🎯 [onLoadStart] Redirect handled, stopping further processing');
                return;
              }

              if (mounted) {
                setState(() => _isLoading = true);
              }
            },
            onLoadStop: (controller, url) async {
              if (_isDisposed || !mounted) return;

              if (_isHandlingRedirect) {
                debugPrint(
                    '$_debugTag - ⏸️ [onLoadStop] Skipping - redirect in progress');
                return;
              }

              debugPrint(
                  '$_debugTag - ✅ [onLoadStop] Page loaded: ${_maskSensitiveUrl(url?.toString() ?? '')}');

              if (_firstLoad && widget.onInitialize != null) {
                widget.onInitialize!();
                _firstLoad = false;
              }

              setState(() => _isLoading = false);
            },
            onReceivedError: (controller, request, error) async {
              final url = request.url.toString();
              debugPrint(
                  '$_debugTag - ❌ [onReceivedError] ${error.description} - URL: ${_maskSensitiveUrl(url)}');

              if (_isDisposed || !mounted) {
                return;
              }

              final handled = await _tryHandleRedirect(
                url,
                controller: controller,
              );

              if (handled) {
                debugPrint(
                    '$_debugTag - 🎯 [onReceivedError] Redirect handled');
                return;
              }

              if (_errorPageShown || _isHandlingRedirect) {
                return;
              }
              debugPrint(
                  '$_debugTag - ⚠️ [onReceivedError] Showing error page: ${error.description} (${error.type})');

              try {
                await controller.stopLoading();
              } catch (_) {}

              try {
                await controller.loadData(
                  data: _getBlankPageHtml(),
                  mimeType: 'text/html',
                  encoding: 'utf-8',
                );
              } catch (_) {}

              if (mounted) {
                setState(() {
                  _errorPageShown = true;
                  _isLoading = false;
                });
              }
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              if (_isDisposed) {
                return NavigationActionPolicy.CANCEL;
              }

              final url = navigationAction.request.url?.toString() ?? '';
              debugPrint(
                  '$_debugTag - 🔀 [shouldOverrideUrlLoading] URL: ${_maskSensitiveUrl(url)}');

              final handled = await _tryHandleRedirect(
                url,
                controller: controller,
              );

              if (handled) {
                debugPrint(
                    '$_debugTag - 🚫 [shouldOverrideUrlLoading] Canceling navigation - redirect handled');
                return NavigationActionPolicy.CANCEL;
              }

              if (_isHandlingRedirect) {
                debugPrint(
                    '$_debugTag - 🚫 [shouldOverrideUrlLoading] Canceling - redirect in progress');
                return NavigationActionPolicy.CANCEL;
              }

              debugPrint(
                  '$_debugTag - ✅ [shouldOverrideUrlLoading] Allowing navigation');
              return NavigationActionPolicy.ALLOW;
            },
            onUpdateVisitedHistory: (controller, url, isReload) async {
              if (_isDisposed || !mounted) {
                return;
              }

              final urlString = url?.toString() ?? '';
              debugPrint(
                  '$_debugTag - 📚 [onUpdateVisitedHistory] URL: ${_maskSensitiveUrl(urlString)}');

              await _tryHandleRedirect(
                urlString,
                controller: controller,
              );
            },
            onProgressChanged: (_, __) {},
            onConsoleMessage: (_, __) {},
            onLoadResource: (controller, resource) async {
              if (_isDisposed || _isHandlingRedirect) {
                return;
              }

              final url = resource.url.toString();
              debugPrint(
                  '$_debugTag - 📦 [onLoadResource] Resource: ${_maskSensitiveUrl(url)}');

              await _tryHandleRedirect(
                url,
                controller: controller,
              );
            },
            shouldInterceptRequest: (controller, request) async {
              if (_isDisposed) {
                return null;
              }

              final url = request.url.toString();
              debugPrint(
                  '$_debugTag - 🔍 [shouldInterceptRequest] URL: ${_maskSensitiveUrl(url)}');

              final handled = await _tryHandleRedirect(
                url,
                controller: controller,
                loadBlankPage: false,
              );

              if (handled || _isHandlingRedirect) {
                debugPrint(
                    '$_debugTag - 🛑 [shouldInterceptRequest] Intercepting request - returning blank response');
                return WebResourceResponse(
                  contentType: 'text/html',
                  contentEncoding: 'utf-8',
                  statusCode: 200,
                  reasonPhrase: 'OK',
                  data: Uint8List.fromList(_getBlankPageHtml().codeUnits),
                );
              }

              return null; // Allow other requests to proceed normally
            },
          ),
          if (_isLoading && !_errorPageShown)
            Container(
              color: backgroundColor,
              child: Center(
                child:
                    widget.loadingWidget ?? const CircularProgressIndicator(),
              ),
            ),
          if (_errorPageShown)
            Builder(
              builder: (context) {
                return Container(
                  color: backgroundColor,
                  child: Center(
                    child: _buildErrorWidget(),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // Helper function to convert Color to hex string (not needed after removing backgroundColor param)
  // Kept for reference in case needed elsewhere
  /// Builds error widget to show as overlay
  Widget _buildErrorWidget() {
    final bgColor = widget.backgroundColor ?? Colors.white;

    return Container(
      color: bgColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon container
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: CustomPaint(
                    size: const Size(40, 40),
                    painter: _ErrorIconPainter(),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // Title
              const Text(
                'Authentication Error',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 16),
              // Message
              const Text(
                'Something went wrong during authentication',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF666666),
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter for error icon (alert circle)
class _ErrorIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF6B6B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Draw circle
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2 - 1,
      paint,
    );

    // Draw exclamation mark line
    paint.style = PaintingStyle.fill;
    paint.strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width / 2, size.height * 0.3),
      Offset(size.width / 2, size.height * 0.55),
      paint..strokeWidth = 2.5,
    );

    // Draw exclamation mark dot
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.7),
      1.5,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

extension on _OAuthWebViewState {
  /// Generates blank page HTML with background color
  String _getBlankPageHtml() {
    String bgColor = 'ffffff';
    if (widget.backgroundColor != null) {
      final color = widget.backgroundColor!;
      bgColor = '${color.red.toRadixString(16).padLeft(2, '0')}'
          '${color.green.toRadixString(16).padLeft(2, '0')}'
          '${color.blue.toRadixString(16).padLeft(2, '0')}';
    }
    return '<html><body style="margin:0;background:#$bgColor;"></body></html>';
  }

  /// Checks if URL is a redirect URL, handling malformed URLs from OAuth providers
  /// Supports any redirect URL format:
  /// - Custom schemes: com.example.app://redirect
  /// - HTTP(S) URLs: http://example.com/callback or https://example.com/callback
  /// - Malformed custom schemes: http://com.example.app//redirect (some OAuth providers do this)
  /// - Hybrid schemes: https://domain://path (some providers incorrectly format like this)
  bool _isRedirectUrl(String url) {
    final redirectUrl = widget.provider.redirectUrl;

    debugPrint('$_debugTag - 🔍 Checking redirect URL');
    debugPrint('$_debugTag - Expected: $redirectUrl');
    debugPrint('$_debugTag - Incoming: $url');

    // 1. Direct prefix match (works for URLs with query parameters)
    // Example: com.example.app://oauth2redirect matches com.example.app://oauth2redirect?code=123
    if (url.startsWith(redirectUrl)) {
      debugPrint('$_debugTag - ✅ YAKALANDI: Direct prefix match');
      return true;
    }

    // 2. Check without query parameters for exact match
    final urlWithoutQuery = url.split('?')[0].split('#')[0];
    if (urlWithoutQuery == redirectUrl) {
      debugPrint('$_debugTag - ✅ YAKALANDI: Exact match without query params');
      return true;
    }

    // 3. Parse and compare URIs
    final redirectUri = Uri.tryParse(redirectUrl);
    final incomingUri = Uri.tryParse(url);

    if (redirectUri != null && incomingUri != null) {
      // Compare schemes (case-insensitive)
      final sameScheme =
          redirectUri.scheme.toLowerCase() == incomingUri.scheme.toLowerCase();

      if (sameScheme) {
        // Get authorities (handle missing authority for custom schemes)
        final redirectAuthority =
            redirectUri.hasAuthority ? redirectUri.authority.toLowerCase() : '';
        final incomingAuthority =
            incomingUri.hasAuthority ? incomingUri.authority.toLowerCase() : '';

        // For custom schemes without authority, compare paths directly
        if (!redirectUri.hasAuthority && !incomingUri.hasAuthority) {
          final redirectPath = redirectUri.path;
          final incomingPath = incomingUri.path;

          if (redirectPath == incomingPath ||
              incomingPath.startsWith(redirectPath)) {
            debugPrint(
                '$_debugTag - ✅ YAKALANDI: Custom scheme path match (scheme: ${redirectUri.scheme})');
            return true;
          }
        }

        // For URLs with authority, compare both authority and path
        if (redirectAuthority == incomingAuthority &&
            redirectAuthority.isNotEmpty) {
          final redirectPath =
              redirectUri.path.isEmpty ? '/' : redirectUri.path;
          final incomingPath =
              incomingUri.path.isEmpty ? '/' : incomingUri.path;

          if (redirectPath == '/' ||
              incomingPath == redirectPath ||
              incomingPath.startsWith('$redirectPath/') ||
              incomingPath.startsWith(redirectPath)) {
            debugPrint(
                '$_debugTag - ✅ YAKALANDI: URI match (scheme: ${redirectUri.scheme}, authority: $redirectAuthority)');
            return true;
          }
        }
      }
    }

    // 4. Check for malformed custom schemes
    if (_matchesMalformedCustomScheme(redirectUrl, url)) {
      return true;
    }

    // 5. Check for hybrid schemes like https://domain://path
    if (_matchesHybridScheme(redirectUrl, url)) {
      return true;
    }

    debugPrint(
        '$_debugTag - ❌ NOT matched: No pattern matched the redirect URL');
    return false;
  }

  /// Checks for malformed custom scheme URLs
  /// Example: com.example.app://path -> http://com.example.app//path
  bool _matchesMalformedCustomScheme(String redirectUrl, String url) {
    if (!redirectUrl.contains('://') ||
        redirectUrl.startsWith('http://') ||
        redirectUrl.startsWith('https://')) {
      return false;
    }

    final parts = redirectUrl.split('://');
    final scheme = parts[0];
    final path = parts.length > 1 ? parts[1] : '';

    // Check http:// prefix malformation
    final httpMalformed = 'http://$scheme//$path';
    if (url.startsWith(httpMalformed) || url.split('?')[0] == httpMalformed) {
      debugPrint('$_debugTag - ✅ YAKALANDI: Malformed custom scheme (http://)');
      debugPrint('$_debugTag - Pattern: $httpMalformed');
      return true;
    }

    // Check https:// prefix malformation
    final httpsMalformed = 'https://$scheme//$path';
    if (url.startsWith(httpsMalformed) || url.split('?')[0] == httpsMalformed) {
      debugPrint(
          '$_debugTag - ✅ YAKALANDI: Malformed custom scheme (https://)');
      debugPrint('$_debugTag - Pattern: $httpsMalformed');
      return true;
    }

    return false;
  }

  /// Checks for hybrid scheme URLs like https://domain://path
  /// Some OAuth providers incorrectly format URLs this way
  bool _matchesHybridScheme(String redirectUrl, String url) {
    // Check if redirect URL has a hybrid format: protocol://domain://path
    if (redirectUrl.contains('://') &&
        redirectUrl.indexOf('://') != redirectUrl.lastIndexOf('://')) {
      // Hybrid format detected in redirect URL
      final normalizedUrl = url.split('?')[0].split('#')[0];
      if (normalizedUrl == redirectUrl || url.startsWith(redirectUrl)) {
        debugPrint('$_debugTag - ✅ YAKALANDI: Hybrid scheme format');
        debugPrint('$_debugTag - Format: [protocol]://[domain]://[path]');
        return true;
      }
    }

    // Check if incoming URL has hybrid format but redirect URL doesn't
    if (url.contains('://') && url.indexOf('://') != url.lastIndexOf('://')) {
      // Try to match the pattern
      final urlParts = url.split('://');
      if (urlParts.length >= 3) {
        // Reconstruct possible redirect URL variations
        final possibleRedirect1 =
            '${urlParts[1]}://${urlParts[2].split('?')[0]}';
        final possibleRedirect2 =
            '${urlParts[0]}://${urlParts[1]}://${urlParts[2].split('?')[0]}';

        if (redirectUrl == possibleRedirect1 ||
            redirectUrl == possibleRedirect2) {
          debugPrint('$_debugTag - ✅ YAKALANDI: Hybrid scheme variation');
          debugPrint(
              '$_debugTag - Matched pattern: $possibleRedirect1 or $possibleRedirect2');
          return true;
        }
      }
    }

    return false;
  }
}

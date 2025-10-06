// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/oauth_provider.dart';
import '../services/oauth_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

class OAuthWebView extends StatefulWidget {
  final OAuthProvider provider;
  final Widget? loadingWidget;
  final Color? backgroundColor;
  final void Function()? onInitialize;
  final bool debugDisableRedirectHandling; // TEST ONLY - prevents redirect handling to see error page

  const OAuthWebView({
    super.key,
    required this.provider,
    this.loadingWidget,
    this.backgroundColor = Colors.white, // Default to white instead of null
    this.onInitialize,
    this.debugDisableRedirectHandling = false, // Default: handle redirects normally
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
    }
  }

  Future<void> _disposeWebView() async {
    if (_webViewController != null) {
      debugPrint('$_debugTag - Disposing WebView controller');
      _webViewController?.dispose();
      _webViewController = null;
    }
  }

  Future<void> _initialize() async {
    if (_isDisposed) return;

    debugPrint('$_debugTag - Starting initialization');
    try {
      await Future.wait([
        _getUserAgent(),
        _loadAuthorizationUrl(),
      ]);
      debugPrint('$_debugTag - Initialization completed successfully');
    } catch (e) {
      debugPrint('$_debugTag - Initialization failed: $e');
      if (!_isDisposed) {
        _initialize();
      }
    }
  }

  Future<void> _getUserAgent() async {
    if (_isDisposed) return;

    debugPrint('$_debugTag - Getting user agent information');
    try {
      final deviceInfo = DeviceInfoPlugin();
      final packageInfo = await PackageInfo.fromPlatform();
      debugPrint(
          '$_debugTag - Package info retrieved: ${packageInfo.appName} ${packageInfo.version}');

      final appVersion = packageInfo.version;

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        debugPrint(
            '$_debugTag - Android device info: ${androidInfo.model} (Android ${androidInfo.version.release})');
        _userAgent =
            'Mozilla/5.0 (Linux; Android ${androidInfo.version.release}; ${androidInfo.model}) '
            'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/Unknown Mobile Safari/537.36 '
            '${packageInfo.appName}/$appVersion';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        debugPrint(
            '$_debugTag - iOS device info: ${iosInfo.model} (iOS ${iosInfo.systemVersion})');
        _userAgent =
            'Mozilla/5.0 (${iosInfo.model}; CPU iPhone OS ${iosInfo.systemVersion.replaceAll('.', '_')} like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1 '
            '${packageInfo.appName}/$appVersion';
      } else {
        debugPrint('$_debugTag - Unknown platform, using default user agent');
        _userAgent =
            'Mozilla/5.0 (Unknown) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';
      }

      debugPrint('$_debugTag - User agent set: $_userAgent');
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

    debugPrint('$_debugTag - Loading authorization URL');
    try {
      final url = await OAuthService.getAuthorizationUrl(widget.provider);
      debugPrint(
          '$_debugTag - Authorization URL loaded: ${_maskSensitiveUrl(url)}');
      if (!_isDisposed && mounted) {
        setState(() => _authorizationUrl = url);
      }
    } catch (e, stackTrace) {
      debugPrint('$_debugTag - Error loading authorization URL: $e');
      debugPrint('$_debugTag - Stack trace: $stackTrace');
      if (!_isDisposed) {
        await Future.delayed(const Duration(seconds: 2));
        if (!_isDisposed && mounted) {
          _loadAuthorizationUrl();
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

    debugPrint('$_debugTag - Building widget, loading: $_isLoading');

    if (_authorizationUrl == null || _userAgent == null) {
      debugPrint(
          '$_debugTag - Showing loading state, authUrl: ${_authorizationUrl != null}, userAgent: ${_userAgent != null}');
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
          // Add a background container to prevent black flash
          Container(
            color: backgroundColor,
            width: double.infinity,
            height: double.infinity,
            child: Center(
              child: widget.loadingWidget ?? const CircularProgressIndicator(),
            ),
          ),
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_authorizationUrl!)),
            initialSettings: InAppWebViewSettings(
              cacheEnabled: false,
              javaScriptEnabled: true,
              userAgent: _userAgent,
              defaultTextEncodingName: 'UTF-8',
              // Set WebView background to be transparent
              transparentBackground: true,
              // Disable default error page to prevent infinite loops
              disableDefaultErrorPage: true,
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;
              debugPrint('$_debugTag - WebView created');
              controller.addJavaScriptHandler(
                handlerName: 'FlutterChannel',
                callback: (args) {
                  debugPrint(
                      '$_debugTag - JavaScript message received: ${args.join(', ')}');
                },
              );
            },
            onLoadStart: (controller, url) async {
              if (!_isDisposed && mounted && !_isHandlingRedirect) {
                final urlString = url?.toString() ?? '';
                debugPrint(
                    '$_debugTag - Page load started: ${_maskSensitiveUrl(urlString)}');

                // Check if this is the redirect URL
                if (_isRedirectUrl(urlString) && !widget.debugDisableRedirectHandling) {
                  _isHandlingRedirect = true;
                  debugPrint(
                      '$_debugTag - Redirect URL matched in onLoadStart, handling OAuth redirect');

                  // IMMEDIATELY stop loading and prevent error page
                  controller.stopLoading();

                  // Load blank page to prevent any error display
                  await controller.loadData(
                    data: _getBlankPageHtml(),
                    mimeType: 'text/html',
                    encoding: 'utf-8',
                  );

                  if (mounted) {
                    setState(() => _isLoading = true);
                  }

                  try {
                    final result =
                        await OAuthService.handleRedirect(urlString, widget.provider);
                    debugPrint(
                        '$_debugTag - OAuth redirect handled successfully');
                    if (!_isDisposed && mounted) {
                      Navigator.of(context).pop(result);
                    }
                  } catch (e, stackTrace) {
                    debugPrint('$_debugTag - ERROR: OAuth redirect failed: $e');
                    debugPrint('$_debugTag - Stack trace: $stackTrace');
                    if (!_isDisposed && mounted) {
                      Navigator.of(context).pop();
                    }
                  }
                  return;
                }

                setState(() => _isLoading = true);
              }
            },
            onLoadStop: (controller, url) async {
              if (!_isDisposed && mounted) {
                debugPrint(
                    '$_debugTag - Page load completed: ${_maskSensitiveUrl(url?.toString() ?? '')}');
                if (_firstLoad && widget.onInitialize != null) {
                  debugPrint('$_debugTag - Calling onInitialize callback');
                  widget.onInitialize!();
                  _firstLoad = false;
                }
                setState(() => _isLoading = false);
              }
            },
            onReceivedError: (controller, request, error) async {
              debugPrint('$_debugTag - onReceivedError called: ${error.description}');
              debugPrint('$_debugTag - URL: ${request.url}');
              debugPrint('$_debugTag - _errorPageShown: $_errorPageShown');

              if (_isDisposed || _errorPageShown) {
                debugPrint('$_debugTag - Skipping error handling (disposed or already shown)');
                return;
              }

              final url = request.url.toString();

              // If error is for redirect URL, show error page
              if (_isRedirectUrl(url)) {
                debugPrint('$_debugTag - ERROR (expected): ${error.description} for redirect URL');
                debugPrint('$_debugTag - Error type: ${error.type}');
                debugPrint('$_debugTag - Setting _errorPageShown = true');

                // Stop any loading
                controller.stopLoading();

                // Set error state - this will show error overlay
                if (mounted) {
                  setState(() {
                    _errorPageShown = true;
                    _isLoading = false;
                  });
                  debugPrint('$_debugTag - State updated: _errorPageShown=$_errorPageShown, _isLoading=$_isLoading');
                }
                return;
              }

              // Real errors - log and reload
              if (!_isHandlingRedirect) {
                debugPrint('$_debugTag - ERROR (unexpected): ${error.description}');
                debugPrint('$_debugTag - Error details: code=${error.type}, url=${_maskSensitiveUrl(url)}');
                controller.reload();
              }
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              if (_isDisposed || _isHandlingRedirect) return NavigationActionPolicy.CANCEL;

              final url = navigationAction.request.url?.toString() ?? '';
              debugPrint(
                  '$_debugTag - URL navigation request: ${_maskSensitiveUrl(url)}');

              if (_isRedirectUrl(url) && !widget.debugDisableRedirectHandling) {
                _isHandlingRedirect = true;
                debugPrint(
                    '$_debugTag - Redirect URL matched in shouldOverrideUrlLoading, handling OAuth redirect');

                // IMMEDIATELY stop loading and prevent error page
                controller.stopLoading();

                // Load blank page to prevent any error display
                await controller.loadData(
                  data: _getBlankPageHtml(),
                  mimeType: 'text/html',
                  encoding: 'utf-8',
                );

                if (mounted) {
                  setState(() => _isLoading = true);
                }

                try {
                  final result =
                      await OAuthService.handleRedirect(url, widget.provider);
                  debugPrint(
                      '$_debugTag - OAuth redirect handled successfully');
                  if (!_isDisposed && mounted) {
                    Navigator.of(context).pop(result);
                  }
                } catch (e, stackTrace) {
                  debugPrint('$_debugTag - ERROR: OAuth redirect failed: $e');
                  debugPrint('$_debugTag - Stack trace: $stackTrace');
                  if (!_isDisposed && mounted) {
                    Navigator.of(context).pop();
                  }
                }
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
            onUpdateVisitedHistory: (controller, url, isReload) async {
              if (!_isDisposed && mounted && !_isHandlingRedirect) {
                final urlString = url?.toString() ?? '';
                debugPrint(
                    '$_debugTag - Visited history updated: ${_maskSensitiveUrl(urlString)}');

                // Check if this is the redirect URL
                if (_isRedirectUrl(urlString) && !widget.debugDisableRedirectHandling) {
                  _isHandlingRedirect = true;
                  debugPrint(
                      '$_debugTag - Redirect URL matched in onUpdateVisitedHistory, handling OAuth redirect');

                  // IMMEDIATELY stop loading and prevent error page
                  controller.stopLoading();

                  // Load blank page to prevent any error display
                  await controller.loadData(
                    data: _getBlankPageHtml(),
                    mimeType: 'text/html',
                    encoding: 'utf-8',
                  );

                  if (mounted) {
                    setState(() => _isLoading = true);
                  }

                  try {
                    final result =
                        await OAuthService.handleRedirect(urlString, widget.provider);
                    debugPrint(
                        '$_debugTag - OAuth redirect handled successfully');
                    if (!_isDisposed && mounted) {
                      Navigator.of(context).pop(result);
                    }
                  } catch (e, stackTrace) {
                    debugPrint('$_debugTag - ERROR: OAuth redirect failed: $e');
                    debugPrint('$_debugTag - Stack trace: $stackTrace');
                    if (!_isDisposed && mounted) {
                      Navigator.of(context).pop();
                    }
                  }
                }
              }
            },
            onProgressChanged: (controller, progress) {
              if (!_isDisposed) {
                debugPrint('$_debugTag - Loading progress: $progress%');
              }
            },
            onConsoleMessage: (controller, consoleMessage) {
              if (!_isDisposed) {
                debugPrint(
                    '$_debugTag - Console [${consoleMessage.messageLevel.toString().toLowerCase()}]: ${consoleMessage.message}');
              }
            },
            onLoadResource: (controller, resource) async {
              if (!_isDisposed && !_isHandlingRedirect) {
                final url = resource.url.toString();

                // 4th safety net: Catch redirect URL at resource load level
                if (_isRedirectUrl(url) && !widget.debugDisableRedirectHandling) {
                  _isHandlingRedirect = true;
                  debugPrint(
                      '$_debugTag - Redirect URL matched in onLoadResource (4th safety net), handling OAuth redirect');

                  // IMMEDIATELY stop loading and prevent error page
                  controller.stopLoading();

                  // Load blank page to prevent any error display
                  await controller.loadData(
                    data: _getBlankPageHtml(),
                    mimeType: 'text/html',
                    encoding: 'utf-8',
                  );

                  if (mounted) {
                    setState(() => _isLoading = true);
                  }

                  try {
                    final result =
                        await OAuthService.handleRedirect(url, widget.provider);
                    debugPrint(
                        '$_debugTag - OAuth redirect handled successfully');
                    if (!_isDisposed && mounted) {
                      Navigator.of(context).pop(result);
                    }
                  } catch (e, stackTrace) {
                    debugPrint('$_debugTag - ERROR: OAuth redirect failed: $e');
                    debugPrint('$_debugTag - Stack trace: $stackTrace');
                    if (!_isDisposed && mounted) {
                      Navigator.of(context).pop();
                    }
                  }
                }
              }
            },
          ),
          if (_errorPageShown)
            Builder(
              builder: (context) {
                debugPrint('$_debugTag - Building error overlay');
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
      bgColor = '${color.r.toInt().toRadixString(16).padLeft(2, '0')}'
          '${color.g.toInt().toRadixString(16).padLeft(2, '0')}'
          '${color.b.toInt().toRadixString(16).padLeft(2, '0')}';
    }
    return '<html><body style="margin:0;background:#$bgColor;"></body></html>';
  }

  /// Checks if URL is a redirect URL, handling malformed URLs from OAuth providers
  /// Supports any redirect URL format:
  /// - Custom schemes: com.example.app://redirect
  /// - HTTP(S) URLs: http://example.com/callback or https://example.com/callback
  /// - Malformed custom schemes: http://com.example.app//redirect (some OAuth providers do this)
  bool _isRedirectUrl(String url) {
    final redirectUrl = widget.provider.redirectUrl;

    // Direct match - works for all formats
    if (url.startsWith(redirectUrl)) return true;

    // Handle malformed custom scheme URLs from OAuth providers
    // Some providers incorrectly convert: com.example.app://path
    // To: http://com.example.app//path (note the double slash)
    // This only applies to custom schemes, not http(s):// URLs
    if (redirectUrl.contains('://') &&
        !redirectUrl.startsWith('http://') &&
        !redirectUrl.startsWith('https://')) {

      final parts = redirectUrl.split('://');
      final scheme = parts[0]; // com.example.app
      final path = parts.length > 1 ? parts[1] : ''; // oauth2redirect

      // Check if URL matches malformed pattern: http://scheme//path
      final malformedPattern = 'http://$scheme//$path';
      if (url.startsWith(malformedPattern)) {
        debugPrint('$_debugTag - MATCHED malformed redirect URL pattern');
        debugPrint('$_debugTag - Expected: $redirectUrl');
        debugPrint('$_debugTag - Got: $url');
        return true;
      }
    }

    return false;
  }
}

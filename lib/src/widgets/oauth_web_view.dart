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
      _initializationAttempts += 1;

      if (_initializationAttempts >= _maxInitializationAttempts) {
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

    _isHandlingRedirect = true;

    if (controller != null) {
      try {
        await controller.stopLoading();
      } catch (e) {}

      if (loadBlankPage) {
        try {
          await controller.loadData(
            data: _getBlankPageHtml(),
            mimeType: 'text/html',
            encoding: 'utf-8',
          );
        } catch (e) {}
      }
    }

    if (mounted && !_isDisposed) {
      setState(() {
        _isLoading = true;
        _errorPageShown = false;
      });
    }

    try {
      final result = await OAuthService.handleRedirect(url, widget.provider);
      if (!_isDisposed && mounted) {
        await Navigator.of(context).maybePop(result);
      }
    } catch (e, stackTrace) {
      if (!_isDisposed && mounted) {
        await Navigator.of(context).maybePop();
      }
    } finally {
      if (!_isDisposed) {
        _isHandlingRedirect = false;
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
    } catch (e) {
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
      if (!_isDisposed) {
        await Future.delayed(_initializationRetryDelay);
        if (!_isDisposed && mounted) {
          await _loadAuthorizationUrl();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDisposed) return const SizedBox();

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
              disableDefaultErrorPage: true,
              supportZoom: false,
              displayZoomControls: false,
              clearCache: true,
              clearSessionCache: true,
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

              final handled = await _tryHandleRedirect(
                urlString,
                controller: controller,
              );

              if (handled) {
                return;
              }

              if (mounted) {
                setState(() => _isLoading = true);
              }
            },
            onLoadStop: (controller, url) async {
              if (_isDisposed || !mounted) return;

              if (_isHandlingRedirect) {
                return;
              }

              if (_firstLoad && widget.onInitialize != null) {
                widget.onInitialize!();
                _firstLoad = false;
              }

              setState(() => _isLoading = false);
            },
            onReceivedError: (controller, request, error) async {
              final url = request.url.toString();

              if (_isDisposed || !mounted) {
                return;
              }

              final handled = await _tryHandleRedirect(
                url,
                controller: controller,
              );

              if (handled) {
                return;
              }

              if (_errorPageShown || _isHandlingRedirect) {
                return;
              }

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

              final handled = await _tryHandleRedirect(
                url,
                controller: controller,
              );

              if (handled) {
                return NavigationActionPolicy.CANCEL;
              }

              if (_isHandlingRedirect) {
                return NavigationActionPolicy.CANCEL;
              }

              return NavigationActionPolicy.ALLOW;
            },
            onUpdateVisitedHistory: (controller, url, isReload) async {
              if (_isDisposed || !mounted) {
                return;
              }

              final urlString = url?.toString() ?? '';

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

              final handled = await _tryHandleRedirect(
                url,
                controller: controller,
                loadBlankPage: false,
              );

              if (handled || _isHandlingRedirect) {
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

class _ErrorIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF6B6B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2 - 1,
      paint,
    );

    paint.style = PaintingStyle.fill;
    paint.strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width / 2, size.height * 0.3),
      Offset(size.width / 2, size.height * 0.55),
      paint..strokeWidth = 2.5,
    );

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
  String _getBlankPageHtml() {
    String bgColor = 'ffffff';
    if (widget.backgroundColor != null) {
      final color = widget.backgroundColor!;
      bgColor = '${color.red.toRadixString(16).padLeft(2, '0')}'
          '${color.green.toRadixString(16).padLeft(2, '0')}'
          '${color.blue.toRadixString(16).padLeft(2, '0')}';
    }
    return '<html><body style=\"margin:0;background:#$bgColor;\"></body></html>';
  }

  bool _isRedirectUrl(String url) {
    final redirectUrl = widget.provider.redirectUrl;

    if (url.startsWith(redirectUrl)) {
      return true;
    }

    final urlWithoutQuery = url.split('?')[0].split('#')[0];
    if (urlWithoutQuery == redirectUrl) {
      return true;
    }

    final redirectUri = Uri.tryParse(redirectUrl);
    final incomingUri = Uri.tryParse(url);

    if (redirectUri != null && incomingUri != null) {
      final sameScheme =
          redirectUri.scheme.toLowerCase() == incomingUri.scheme.toLowerCase();

      if (sameScheme) {
        final redirectAuthority =
            redirectUri.hasAuthority ? redirectUri.authority.toLowerCase() : '';
        final incomingAuthority =
            incomingUri.hasAuthority ? incomingUri.authority.toLowerCase() : '';

        if (!redirectUri.hasAuthority && !incomingUri.hasAuthority) {
          final redirectPath = redirectUri.path;
          final incomingPath = incomingUri.path;

          if (redirectPath == incomingPath ||
              incomingPath.startsWith(redirectPath)) {
            return true;
          }
        }

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
            return true;
          }
        }
      }
    }

    if (_matchesMalformedCustomScheme(redirectUrl, url)) {
      return true;
    }

    if (_matchesHybridScheme(redirectUrl, url)) {
      return true;
    }

    return false;
  }

  bool _matchesMalformedCustomScheme(String redirectUrl, String url) {
    if (!redirectUrl.contains('://') ||
        redirectUrl.startsWith('http://') ||
        redirectUrl.startsWith('https://')) {
      return false;
    }

    final parts = redirectUrl.split('://');
    final scheme = parts[0];
    final path = parts.length > 1 ? parts[1] : '';

    final httpMalformed = 'http://$scheme//$path';
    if (url.startsWith(httpMalformed) || url.split('?')[0] == httpMalformed) {
      return true;
    }

    final httpsMalformed = 'https://$scheme//$path';
    if (url.startsWith(httpsMalformed) || url.split('?')[0] == httpsMalformed) {
      return true;
    }

    return false;
  }

  bool _matchesHybridScheme(String redirectUrl, String url) {
    if (redirectUrl.contains('://') &&
        redirectUrl.indexOf('://') != redirectUrl.lastIndexOf('://')) {
      final normalizedUrl = url.split('?')[0].split('#')[0];
      if (normalizedUrl == redirectUrl || url.startsWith(redirectUrl)) {
        return true;
      }
    }

    if (url.contains('://') && url.indexOf('://') != url.lastIndexOf('://')) {
      final urlParts = url.split('://');
      if (urlParts.length >= 3) {
        final possibleRedirect1 =
            '${urlParts[1]}://${urlParts[2].split('?')[0]}';
        final possibleRedirect2 =
            '${urlParts[0]}://${urlParts[1]}://${urlParts[2].split('?')[0]}';

        if (redirectUrl == possibleRedirect1 ||
            redirectUrl == possibleRedirect2) {
          return true;
        }
      }
    }

    return false;
  }
}

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

  const OAuthWebView({
    super.key,
    required this.provider,
    this.loadingWidget,
    this.backgroundColor,
    this.onInitialize,
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

    debugPrint('$_debugTag - Building widget, loading: $_isLoading');

    if (_authorizationUrl == null || _userAgent == null) {
      debugPrint(
          '$_debugTag - Showing loading state, authUrl: ${_authorizationUrl != null}, userAgent: ${_userAgent != null}');
      return Scaffold(
        backgroundColor: widget.backgroundColor,
        body: Center(
          child: widget.loadingWidget ?? const CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: widget.backgroundColor,
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_authorizationUrl!)),
            initialSettings: InAppWebViewSettings(
              cacheEnabled: false,
              javaScriptEnabled: true,
              userAgent: _userAgent,
              defaultTextEncodingName: 'UTF-8',
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
            onLoadStart: (controller, url) {
              if (!_isDisposed && mounted) {
                debugPrint(
                    '$_debugTag - Page load started: ${_maskSensitiveUrl(url?.toString() ?? '')}');
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
            onReceivedError: (controller, request, error) {
              if (!_isDisposed) {
                debugPrint('$_debugTag - WebView error: ${error.description}');
                debugPrint(
                    '$_debugTag - Error details: code=${error.type}, description=${error.description}');
                controller.reload();
              }
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              if (_isDisposed) return NavigationActionPolicy.CANCEL;

              final url = navigationAction.request.url?.toString() ?? '';
              debugPrint(
                  '$_debugTag - URL navigation request: ${_maskSensitiveUrl(url)}');

              if (url.startsWith(widget.provider.redirectUrl)) {
                debugPrint(
                    '$_debugTag - Redirect URL matched, handling OAuth redirect');
                try {
                  final result =
                      await OAuthService.handleRedirect(url, widget.provider);
                  debugPrint(
                      '$_debugTag - OAuth redirect handled successfully');
                  if (!_isDisposed && mounted) {
                    Navigator.of(context).pop(result);
                  }
                } catch (e, stackTrace) {
                  debugPrint('$_debugTag - Error handling redirect: $e');
                  debugPrint('$_debugTag - Stack trace: $stackTrace');
                  if (!_isDisposed && mounted) {
                    Navigator.of(context).pop();
                  }
                }
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
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
          ),
          if (_isLoading)
            Center(
              child: widget.loadingWidget ?? const CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    debugPrint('$_debugTag - Disposing widget');
    _isDisposed = true;
    _disposeWebView();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

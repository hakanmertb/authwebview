import 'dart:developer';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/oauth_provider.dart';
import '../services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

class OAuthWebView extends StatefulWidget {
  final OAuthProvider provider;
  final Widget? loadingWidget;
  final Color? backgroundColor;

  const OAuthWebView(
      {super.key,
      required this.provider,
      this.loadingWidget,
      this.backgroundColor});

  @override
  State<OAuthWebView> createState() => _OAuthWebViewState();
}

class _OAuthWebViewState extends State<OAuthWebView> {
  WebViewController? _controller;
  bool _isLoading = true;
  String? _error;
  String? _userAgent;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  Future<void> _getUserAgent() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    String appVersion = packageInfo.version;

    if (defaultTargetPlatform == TargetPlatform.android) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      String manufacturer = androidInfo.manufacturer;
      String model = androidInfo.model;
      String buildId = androidInfo.id;
      String osVersion = androidInfo.version.release;
      String webViewVersion = 'unknown';

      _userAgent =
          'Mozilla/5.0 (Linux; Android $osVersion; $manufacturer $model Build/$buildId) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/$webViewVersion Mobile Safari/537.36 '
          '${packageInfo.appName}/$appVersion';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      String osVersion = iosInfo.systemVersion;
      String model = iosInfo.model;

      _userAgent =
          'Mozilla/5.0 (${model.replaceAll(',', ';')}; CPU iPhone OS ${osVersion.replaceAll('.', '_')} like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) '
          'Version/15.0 Mobile/15E148 Safari/604.1 '
          '${packageInfo.appName}/$appVersion';
    } else {
      _userAgent =
          'Mozilla/5.0 (Unknown; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';
    }
  }

  Future<void> _initializeWebView() async {
    try {
      await _getUserAgent();
      final authorizationUrl =
          await AuthService.getAuthorizationUrl(widget.provider);
      log("User Agent: $_userAgent");

      final controller = WebViewController()
        ..setUserAgent(_userAgent ?? '')
        ..clearCache()
        ..clearLocalStorage()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              log('Page load started: $url', name: 'OAuthWebView');
              if (mounted) setState(() => _isLoading = true);
            },
            onPageFinished: (String url) {
              log('Page load finished: $url', name: 'OAuthWebView');
              if (mounted) setState(() => _isLoading = false);
            },
            onNavigationRequest: (NavigationRequest request) {
              log('Navigation request: ${request.url}', name: 'OAuthWebView');
              if (request.url.startsWith(widget.provider.redirectUrl)) {
                log('Redirect URL detected, processing...',
                    name: 'OAuthWebView');
                AuthService.handleRedirect(request.url, widget.provider)
                    .then((result) {
                  if (mounted) Navigator.of(context).pop(result);
                });
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
            onWebResourceError: (WebResourceError error) {
              log('WebView error: ${error.description}',
                  name: 'OAuthWebView', error: error);
              if (mounted)
                setState(() => _error = 'WebView error: ${error.description}');
            },
          ),
        )
        ..addJavaScriptChannel(
          'FlutterChannel',
          onMessageReceived: _onJavaScriptMessage,
        )
        ..setOnConsoleMessage(_onConsoleMessage)
        ..loadRequest(Uri.parse(authorizationUrl))
        ..setBackgroundColor(
          widget.backgroundColor ?? Colors.white,
        );

      // JavaScript kanallarının eklenmesinden önce JavaScript'in doğru şekilde yüklendiğinden emin ol
      await controller.runJavaScript('''
        window.onerror = function(message, source, lineno, colno, error) {
          FlutterChannel.postMessage(JSON.stringify({
            type: 'error',
            message: message,
            source: source,
            lineno: lineno,
            colno: colno,
            error: error ? error.stack : null
          }));
        };

        var originalFetch = window.fetch;
        window.fetch = function() {
          FlutterChannel.postMessage(JSON.stringify({
            type: 'fetch',
            url: arguments[0],
            options: arguments[1]
          }));
          return originalFetch.apply(this, arguments);
        };
      ''');

      if (mounted) setState(() => _controller = controller);
    } catch (e) {
      log('Error initializing WebView: $e', name: 'OAuthWebView', error: e);
      debugPrint(e.toString());
      rethrow;
    }
  }

  void _onJavaScriptMessage(JavaScriptMessage message) {
    final data = jsonDecode(message.message);
    switch (data['type']) {
      case 'pageSource':
        log('Page source: ${data['content']}', name: 'OAuthWebView');
        break;
      case 'error':
        log('JavaScript error: ${data['message']} at ${data['source']}:${data['lineno']}:${data['colno']}',
            name: 'OAuthWebView');
        break;
      case 'fetch':
        log('Fetch request: ${data['url']}', name: 'OAuthWebView');
        break;
    }
  }

  void _onConsoleMessage(JavaScriptConsoleMessage message) {
    log('Console ${message.level.name}: ${message.message}',
        name: 'OAuthWebView');
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    return Scaffold(
      backgroundColor: widget.backgroundColor ?? Colors.white,
      body: Stack(
        children: [
          if (_controller != null) WebViewWidget(controller: _controller!),
          if (_isLoading || _controller == null)
            Center(
              child: widget.loadingWidget ?? const CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

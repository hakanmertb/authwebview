import 'dart:developer' as developer;
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

  const OAuthWebView({
    super.key,
    required this.provider,
    this.loadingWidget,
    this.backgroundColor,
  });

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
            'Mozilla/5.0 (Unknown; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';
      }
    } catch (e) {
      developer.log('Error getting user agent: $e', name: 'OAuthWebView');
      _userAgent =
          'Mozilla/5.0 (Unknown) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Mobile Safari/537.36';
    }
  }

  Future<void> _initializeWebView() async {
    try {
      await _getUserAgent();
      final authorizationUrl =
          await AuthService.getAuthorizationUrl(widget.provider);

      final controller = WebViewController()
        ..setUserAgent(_userAgent ?? '')
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(_buildNavigationDelegate())
        ..addJavaScriptChannel('FlutterChannel',
            onMessageReceived: _onJavaScriptMessage)
        ..setBackgroundColor(widget.backgroundColor ?? Colors.white);

      await controller.loadRequest(Uri.parse(authorizationUrl));

      if (mounted) setState(() => _controller = controller);
    } catch (e) {
      developer.log('Error initializing WebView: $e', name: 'OAuthWebView');
      setState(() => _error = 'Failed to initialize. Please try again.');
    }
  }

  NavigationDelegate _buildNavigationDelegate() {
    return NavigationDelegate(
      onPageStarted: (String url) {
        if (mounted) setState(() => _isLoading = true);
      },
      onPageFinished: (String url) async {
        if (mounted) setState(() => _isLoading = false);
      },
      onNavigationRequest: (NavigationRequest request) {
        if (request.url.startsWith(widget.provider.redirectUrl)) {
          AuthService.handleRedirect(request.url, widget.provider)
              .then((result) {
            if (mounted) Navigator.of(context).pop(result);
          });
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      },
      onWebResourceError: (WebResourceError error) {
        developer.log('WebView error: ${error.description}',
            name: 'OAuthWebView');
        if (mounted) {
          setState(() => _error = 'An error occurred. Please try again.');
        }
      },
    );
  }

  void _onJavaScriptMessage(JavaScriptMessage message) {
    developer.log('Received message from JavaScript', name: 'OAuthWebView');
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

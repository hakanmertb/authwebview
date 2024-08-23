import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/oauth_provider.dart';
import '../services/auth_service.dart';

class OAuthWebView extends StatefulWidget {
  final OAuthProvider provider;
  final Widget? loadingWidget;

  const OAuthWebView({
    super.key,
    required this.provider,
    this.loadingWidget,
  });

  @override
  State<OAuthWebView> createState() => _OAuthWebViewState();
}

class _OAuthWebViewState extends State<OAuthWebView> {
  WebViewController? _controller;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  String _manipulateUserAgent(String originalUserAgent) {
    originalUserAgent = originalUserAgent.replaceAll(RegExp(r'wv|WebView'), '');
    originalUserAgent = originalUserAgent.replaceAll(
        RegExp(r'Android SDK built for x86|Emulator'), 'Android Device');
    originalUserAgent = originalUserAgent.replaceAll(RegExp(r'Flutter'), '');
    if (Platform.isAndroid) {
      originalUserAgent = originalUserAgent.replaceAll(
          RegExp(r'Mobile Safari/[.\d]+'), 'Mobile Safari/537.36');
    } else if (Platform.isIOS) {
      originalUserAgent = originalUserAgent.replaceAll(
          RegExp(r'Mobile/[^\s]+'), 'Mobile/15E148');
    }
    return originalUserAgent.trim();
  }

  Future<String> _getUserAgent() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.loadRequest(Uri.parse('about:blank'));
      final userAgent =
          await controller.runJavaScriptReturningResult('navigator.userAgent');
      return _manipulateUserAgent(userAgent.toString());
    } else {
      return 'Mozilla/5.0 (Unknown; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';
    }
  }

  Future<void> _initializeWebView() async {
    try {
      final authorizationUrl =
          await AuthService.getAuthorizationUrl(widget.provider);
      final userAgent = await _getUserAgent();
      log(userAgent);
      final controller = WebViewController()
        ..setUserAgent(
            "Mozilla/5.0 (Linux; Android 7.1; LG-H900 Build/NRD90C) AppleWebKit/603.33 (KHTML, like Gecko)  Chrome/47.0.1863.197 Mobile Safari/535.5")
        ..clearCache()
        ..clearLocalStorage()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) =>
                mounted ? setState(() => _isLoading = true) : null,
            onPageFinished: (_) =>
                mounted ? setState(() => _isLoading = false) : null,
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
              mounted
                  ? setState(
                      () => _error = 'WebView hatası: ${error.description}')
                  : null;
            },
          ),
        )
        ..loadRequest(Uri.parse(authorizationUrl));

      await controller
          .runJavaScript('document.cookie = "";'); // Çerezleri temizle
      mounted ? setState(() => _controller = controller) : null;
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
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

import 'dart:developer';
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
      // WebView.platform.getVersionInfo() kaldırıldı
      String webViewVersion = 'unknown';

      _userAgent =
          'Mozilla/5.0 (Linux; Android $osVersion; $manufacturer $model Build/$buildId) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/$webViewVersion Mobile Safari/537.36 '
          '${packageInfo.appName}/$appVersion';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      String osVersion = iosInfo.systemVersion; // ?? operatörü kaldırıldı
      String model = iosInfo.model; // ?? operatörü kaldırıldı

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
        ..loadRequest(Uri.parse(authorizationUrl))
        ..setBackgroundColor(
          widget.backgroundColor ?? Colors.white,
        );

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

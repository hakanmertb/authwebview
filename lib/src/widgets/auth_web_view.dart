import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/oauth_provider.dart';
import '../services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';

class OAuthWebView extends StatefulWidget {
  final OAuthProvider provider;
  final Widget? loadingWidget;
  final void Function()? initFunc;

  const OAuthWebView({
    super.key,
    required this.provider,
    this.loadingWidget,
    this.initFunc,
  });

  @override
  State<OAuthWebView> createState() => _OAuthWebViewState();
}

class _OAuthWebViewState extends State<OAuthWebView> {
  bool _isLoading = true;
  String? _error;
  bool _firstLoading = true;
  String? _authorizationUrl;
  String? _userAgent;

  @override
  void initState() {
    super.initState();
    _loadAuthorizationUrl();
    _getUserAgent();
  }

  Future<void> _getUserAgent() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (defaultTargetPlatform == TargetPlatform.android) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      _userAgent =
          'Mozilla/5.0 (Linux; Android ${androidInfo.version.release}; ${androidInfo.model}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/88.0.4324.181 Mobile Safari/537.36';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      _userAgent =
          'Mozilla/5.0 (iPhone; CPU iPhone OS ${iosInfo.systemVersion?.replaceAll('.', '_')} like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1';
    }
    setState(() {});
  }

  Future<void> _loadAuthorizationUrl() async {
    try {
      final url = await AuthService.getAuthorizationUrl(widget.provider);
      if (mounted) {
        setState(() {
          _authorizationUrl = url;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error loading authorization URL: $e';
        });
      }
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

    if (_authorizationUrl == null || _userAgent == null) {
      return Scaffold(
        body: Center(
          child: widget.loadingWidget ?? const CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_authorizationUrl!)),
            initialSettings: InAppWebViewSettings(
              cacheEnabled: false,
              javaScriptEnabled: true,
              userAgent: _userAgent,
            ),
            onLoadStart: (controller, url) {
              if (mounted) setState(() => _isLoading = true);
            },
            onLoadStop: (controller, url) {
              if (mounted) {
                if (_firstLoading && widget.initFunc != null) {
                  widget.initFunc!();
                  _firstLoading = false;
                }
                setState(() => _isLoading = false);
              }
            },
            onReceivedError: (controller, request, error) {
              if (mounted) {
                setState(() => _error = 'WebView error: ${error.description}');
              }
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              var uri = navigationAction.request.url!;
              if (uri.toString().startsWith(widget.provider.redirectUrl)) {
                final result = await AuthService.handleRedirect(
                    uri.toString(), widget.provider);
                if (mounted) {
                  Navigator.of(context).pop(result);
                }
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
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
}

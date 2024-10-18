import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:authwebview/src/widgets/auth_web_view.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/oauth_provider.dart';
import '../models/authorization_token_response.dart';
import '../utils/crypto_utils.dart';

class AuthService {
  static String _state = '';
  static String _codeVerifier = '';
  static String _codeChallenge = '';

  static Future<AuthorizationTokenResponse?> performOAuthFlow(
      BuildContext context, OAuthProvider provider,
      {Widget? loadingWidget, Color? backgroundColor}) async {
    try {
      return await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OAuthWebView(
            provider: provider,
            loadingWidget: loadingWidget,
            backgroundColor: backgroundColor,
          ),
        ),
      );
    } catch (e) {
      debugPrint('OAuth flow error: $e');
      return null;
    }
  }

  static Future<bool> logout(OAuthProvider provider, String idTokenHint) async {
    try {
      final discoveryResponse =
          await http.get(Uri.parse(provider.discoveryUrl));
      if (discoveryResponse.statusCode != 200) {
        throw Exception('Failed to fetch discovery document');
      }

      final discoveryData = json.decode(discoveryResponse.body);
      final endSessionEndpoint = discoveryData['end_session_endpoint'];

      if (endSessionEndpoint == null) {
        throw Exception('End session endpoint not found in discovery document');
      }

      final logoutResponse = await http
          .get(Uri.parse(endSessionEndpoint).replace(queryParameters: {
        'id_token_hint': idTokenHint,
      }));
      log(logoutResponse.body);
      return logoutResponse.statusCode == 200;
    } catch (e) {
      debugPrint('Logout error: $e');
      return false;
    }
  }

  static Future<String> getAuthorizationUrl(OAuthProvider provider) async {
    _state = CryptoUtils.generateRandomString(32);
    _codeVerifier = CryptoUtils.generateRandomString(128);
    _codeChallenge = CryptoUtils.generateCodeChallenge(_codeVerifier);

    try {
      final discoveryResponse =
          await http.get(Uri.parse(provider.discoveryUrl));
      if (discoveryResponse.statusCode != 200) {
        throw Exception('Failed to fetch discovery document');
      }

      final discoveryData = json.decode(discoveryResponse.body);
      final authorizationEndpoint = discoveryData['authorization_endpoint'];

      return Uri.parse(authorizationEndpoint).replace(
        queryParameters: {
          'response_type': 'code',
          'client_id': provider.clientId,
          'redirect_uri': provider.redirectUrl,
          'scope': provider.scopes.join(' '),
          'state': _state,
          'code_challenge': _codeChallenge,
          'code_challenge_method': 'S256',
        },
      ).toString();
    } catch (e) {
      throw Exception('Failed to get authorization URL: $e');
    }
  }

  static Future<AuthorizationTokenResponse?> handleRedirect(
      String url, OAuthProvider provider) async {
    try {
      final uri = Uri.parse(url);
      final code = uri.queryParameters['code'];
      final returnedState = uri.queryParameters['state'];

      if (returnedState != _state) {
        throw Exception('Invalid state parameter');
      }

      if (code != null) {
        return await _exchangeCodeForToken(code, provider);
      } else {
        throw Exception('No authorization code found in redirect URL');
      }
    } catch (e) {
      debugPrint('Error handling redirect: $e');
      return null;
    }
  }

  static Future<AuthorizationTokenResponse?> _exchangeCodeForToken(
      String code, OAuthProvider provider) async {
    try {
      final discoveryResponse =
          await http.get(Uri.parse(provider.discoveryUrl));
      final discoveryData = json.decode(discoveryResponse.body);
      final tokenEndpoint = discoveryData['token_endpoint'];

      final response = await http.post(
        Uri.parse(tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': provider.redirectUrl,
          'client_id': provider.clientId,
          'code_verifier': _codeVerifier,
        },
      );

      if (response.statusCode == 200) {
        final tokenData = json.decode(response.body);
        return AuthorizationTokenResponse.fromJson(tokenData);
      } else {
        throw Exception('Failed to get token: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error during token exchange: $e');
      return null;
    }
  }
}

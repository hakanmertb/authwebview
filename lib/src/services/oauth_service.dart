import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/oauth_provider.dart';
import '../models/authorization_token_response.dart';
import '../utils/crypto_utils.dart';
import '../exceptions/oauth_exception.dart';
import '../widgets/oauth_web_view.dart';

/// A service that handles OAuth 2.0 authentication flow with PKCE support.
class OAuthService {
  static String _state = '';
  static String _codeVerifier = '';
  static String _codeChallenge = '';
  static http.Client _client = http.Client();

  /// For testing purposes only
  @visibleForTesting
  static void setHttpClient(http.Client client) {
    _client = client;
  }

  /// Returns the current state parameter for testing purposes
  @visibleForTesting
  static String getState() => _state;

  /// Performs the OAuth authentication flow using a WebView.
  /// 
  /// Shows a WebView for user authentication and handles the redirect.
  /// Returns an [AuthorizationTokenResponse] if successful, null otherwise.
  static Future<AuthorizationTokenResponse?> performOAuthFlow(
    BuildContext context,
    OAuthProvider provider, {
    Widget? loadingWidget,
    Color? backgroundColor,
    void Function(String)? onError,
  }) async {
    try {
      dev.log('Starting OAuth flow for provider: ${provider.name}');
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
    } catch (e, stackTrace) {
      dev.log(
        'OAuth flow error',
        error: e,
        stackTrace: stackTrace,
      );
      onError?.call(e.toString());
      return null;
    }
  }

  /// Performs the logout process for the authenticated user.
  /// 
  /// Uses the provider's end_session_endpoint from the discovery document.
  /// Returns true if logout was successful.
  static Future<bool> logout(OAuthProvider provider, String idTokenHint) async {
    try {
      dev.log('Starting logout process for provider: ${provider.name}');
      
      final discoveryData = await _fetchDiscoveryDocument(provider);
      final endSessionEndpoint = discoveryData['end_session_endpoint'];

      if (endSessionEndpoint == null) {
        throw const OAuthException(
          message: 'End session endpoint not found in discovery document',
          code: 'missing_endpoint',
        );
      }

      final logoutResponse = await _client.get(
        Uri.parse(endSessionEndpoint).replace(
          queryParameters: {'id_token_hint': idTokenHint},
        ),
      );

      dev.log('Logout response status: ${logoutResponse.statusCode}');
      return logoutResponse.statusCode == 200;
    } catch (e, stackTrace) {
      dev.log(
        'Logout error',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Generates an authorization URL for the OAuth flow.
  /// 
  /// Includes PKCE parameters and state for security.
  static Future<String> getAuthorizationUrl(OAuthProvider provider) async {
    try {
      _state = CryptoUtils.generateRandomString(32);
      _codeVerifier = CryptoUtils.generateRandomString(128);
      _codeChallenge = CryptoUtils.generateCodeChallenge(_codeVerifier);

      final discoveryData = await _fetchDiscoveryDocument(provider);
      final authorizationEndpoint = discoveryData['authorization_endpoint'];

      if (authorizationEndpoint == null) {
        throw const OAuthException(
          message: 'Authorization endpoint not found in discovery document',
          code: 'missing_endpoint',
        );
      }

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
    } catch (e, stackTrace) {
      dev.log(
        'Error generating authorization URL',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Handles the redirect URL after authorization.
  /// 
  /// Validates the state parameter and exchanges the code for tokens.
  static Future<AuthorizationTokenResponse?> handleRedirect(
    String url,
    OAuthProvider provider,
  ) async {
    try {
      final uri = Uri.parse(url);
      final error = uri.queryParameters['error'];
      
      if (error != null) {
        throw OAuthException.fromOAuthError(
          Map<String, String>.from(uri.queryParameters),
        );
      }

      final code = uri.queryParameters['code'];
      final returnedState = uri.queryParameters['state'];

      if (returnedState != _state) {
        throw const OAuthException(
          message: 'Invalid state parameter',
          code: 'invalid_state',
        );
      }

      if (code == null) {
        throw const OAuthException(
          message: 'No authorization code found in redirect URL',
          code: 'missing_code',
        );
      }

      return await _exchangeCodeForToken(code, provider);
    } catch (e, stackTrace) {
      dev.log(
        'Error handling redirect',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Fetches the OpenID Connect discovery document.
  static Future<Map<String, dynamic>> _fetchDiscoveryDocument(
    OAuthProvider provider,
  ) async {
    try {
      final response = await _client.get(Uri.parse(provider.discoveryUrl));
      
      if (response.statusCode != 200) {
        throw const OAuthException(
          message: 'Failed to fetch discovery document',
          code: 'discovery_error',
          description: 'Invalid status code',
        );
      }

      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      if (e is OAuthException) rethrow;
      throw OAuthException(
        message: 'Failed to fetch discovery document',
        code: 'discovery_error',
        originalError: e,
      );
    }
  }

  /// Exchanges an authorization code for tokens.
  static Future<AuthorizationTokenResponse?> _exchangeCodeForToken(
    String code,
    OAuthProvider provider,
  ) async {
    try {
      final discoveryData = await _fetchDiscoveryDocument(provider);
      final tokenEndpoint = discoveryData['token_endpoint'] as String?;

      if (tokenEndpoint == null) {
        throw const OAuthException(
          message: 'Token endpoint not found in discovery document',
          code: 'missing_endpoint',
        );
      }

      final response = await _client.post(
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
        throw OAuthException(
          message: 'Failed to exchange code for token',
          code: 'token_error',
          description: 'Status code: ${response.statusCode}',
          originalError: response.body,
        );
      }
    } catch (e, stackTrace) {
      dev.log(
        'Error during token exchange',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}
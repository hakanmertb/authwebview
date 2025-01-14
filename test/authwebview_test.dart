import 'dart:convert';
import 'package:authwebview/src/exceptions/oauth_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:authwebview/authwebview.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:http/http.dart' as http;

@GenerateMocks([http.Client])
import 'authwebview_test.mocks.dart';

void main() {
  late MockClient mockHttpClient;
  late OAuthProvider testProvider;

  setUp(() {
    mockHttpClient = MockClient();
    OAuthService.setHttpClient(mockHttpClient); // Set the mock client

    testProvider = const OAuthProvider(
      name: 'Test Provider',
      discoveryUrl: 'https://example.com/.well-known/openid-configuration',
      clientId: 'test-client-id',
      redirectUrl: 'com.example.app://callback',
    );
  });

  tearDown(() {
    // Reset to default client after each test
    OAuthService.setHttpClient(http.Client());
  });

  group('OAuthService', () {
    test('getAuthorizationUrl generates valid URL with all required parameters',
        () async {
      // Mock the discovery document response
      when(mockHttpClient.get(Uri.parse(testProvider.discoveryUrl))).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'authorization_endpoint': 'https://example.com/auth'}),
          200,
        ),
      );

      final url = await OAuthService.getAuthorizationUrl(testProvider);

      expect(url, isA<String>());
      expect(url, contains('response_type=code'));
      expect(url, contains('client_id=${testProvider.clientId}'));
      expect(
          url,
          contains(
              'redirect_uri=${Uri.encodeComponent(testProvider.redirectUrl)}'));
      expect(url, contains('code_challenge_method=S256'));
      expect(url, contains('state='));
      expect(url, contains('code_challenge='));

      // Verify the HTTP call was made
      verify(mockHttpClient.get(Uri.parse(testProvider.discoveryUrl)))
          .called(1);
    });

    test('handleRedirect validates state parameter', () async {
      // Mock discovery document for token endpoint
      when(mockHttpClient.get(Uri.parse(testProvider.discoveryUrl))).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'authorization_endpoint': 'https://example.com/auth',
            'token_endpoint': 'https://example.com/token'
          }),
          200,
        ),
      );

      // First get authorization URL to set up state
      await OAuthService.getAuthorizationUrl(testProvider);

      const invalidRedirectUrl =
          'com.example.app://callback?code=test_code&state=invalid_state';
      final result =
          await OAuthService.handleRedirect(invalidRedirectUrl, testProvider);

      expect(result, isNull);
    });

    test('handleRedirect successfully exchanges code for token', () async {
      // First mock the discovery document request for getting the authorization URL
      when(mockHttpClient.get(Uri.parse(testProvider.discoveryUrl))).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'authorization_endpoint': 'https://example.com/auth',
            'token_endpoint': 'https://example.com/token'
          }),
          200,
        ),
      );

      // Get authorization URL to set up state
      await OAuthService.getAuthorizationUrl(testProvider);

      // Mock the token endpoint response
      const tokenEndpoint = 'https://example.com/token';
      when(
        mockHttpClient.post(
          Uri.parse(tokenEndpoint),
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'access_token': 'test_token',
            'token_type': 'Bearer',
            'expires_in': 3600
          }),
          200,
        ),
      );

      final redirectUrl =
          'com.example.app://callback?code=test_code&state=${OAuthService.getState()}';
      final result =
          await OAuthService.handleRedirect(redirectUrl, testProvider);

      expect(result, isNotNull);
      expect(result?.accessToken, equals('test_token'));
      expect(result?.tokenType, equals('Bearer'));

      // Verify all HTTP calls were made
      verify(mockHttpClient.get(Uri.parse(testProvider.discoveryUrl)))
          .called(2);
      verify(
        mockHttpClient.post(
          Uri.parse(tokenEndpoint),
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).called(1);
    });

    test('handleRedirect returns null when token exchange fails', () async {
      // Mock discovery document
      when(mockHttpClient.get(Uri.parse(testProvider.discoveryUrl))).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'authorization_endpoint': 'https://example.com/auth',
            'token_endpoint': 'https://example.com/token'
          }),
          200,
        ),
      );

      // Get authorization URL to set up state
      await OAuthService.getAuthorizationUrl(testProvider);

      // Mock failed token endpoint response
      const tokenEndpoint = 'https://example.com/token';
      when(
        mockHttpClient.post(
          Uri.parse(tokenEndpoint),
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'error': 'invalid_grant',
            'error_description': 'Invalid authorization code'
          }),
          400,
        ),
      );

      final redirectUrl =
          'com.example.app://callback?code=test_code&state=${OAuthService.getState()}';
      final result =
          await OAuthService.handleRedirect(redirectUrl, testProvider);

      expect(result, isNull);
    });

    test('getAuthorizationUrl throws exception when discovery fails', () async {
      // Mock failed discovery document response
      when(mockHttpClient.get(Uri.parse(testProvider.discoveryUrl))).thenAnswer(
        (_) async => http.Response(
          'Not Found',
          404,
        ),
      );

      expect(
        () => OAuthService.getAuthorizationUrl(testProvider),
        throwsA(isA<OAuthException>()),
      );
    });
  });
}

import 'package:authwebview/authwebview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AuthWebView Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AuthorizationTokenResponse? _tokenResponse;
  bool _isLoading = true;
  final storage = const FlutterSecureStorage();

  final List<OAuthProvider> _providers = [
    // Example Google provider
    const OAuthProvider(
      name: 'Google',
      discoveryUrl:
          'https://accounts.google.com/.well-known/openid-configuration',
      clientId: 'your-client-id',
      redirectUrl: 'com.example.app:/oauth2callback',
      scopes: ['openid', 'profile', 'email'],
    ),
    // Example Microsoft provider
    const OAuthProvider(
      name: 'Microsoft',
      discoveryUrl:
          'https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration',
      clientId: 'your-client-id',
      redirectUrl: 'com.example.app:/oauth2callback',
      scopes: ['openid', 'profile', 'email', 'offline_access'],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedTokens();
  }

  Future<void> _loadSavedTokens() async {
    try {
      final tokenJson = await storage.read(key: 'oauth_tokens');
      if (tokenJson != null) {
        setState(() {
          _tokenResponse = AuthorizationTokenResponse.fromJson(
            json.decode(tokenJson),
          );
        });
      }
    } catch (e) {
      debugPrint('Error loading saved tokens: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveTokens(AuthorizationTokenResponse tokens) async {
    try {
      await storage.write(
        key: 'oauth_tokens',
        value: json.encode(tokens.toJson()),
      );
    } catch (e) {
      debugPrint('Error saving tokens: $e');
    }
  }

  Future<void> _clearTokens() async {
    try {
      await storage.delete(key: 'oauth_tokens');
    } catch (e) {
      debugPrint('Error clearing tokens: $e');
    }
  }

  Future<void> _login(OAuthProvider provider) async {
    try {
      final result = await OAuthService.performOAuthFlow(
        context,
        provider,
        loadingWidget: const Center(child: CircularProgressIndicator()),
        backgroundColor: Theme.of(
          context,
        ).colorScheme.surface, // background -> surface
      );

      if (result != null) {
        setState(() {
          _tokenResponse = result;
        });
        await _saveTokens(result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _logout(OAuthProvider provider) async {
    if (_tokenResponse?.idToken == null) {
      setState(() {
        _tokenResponse = null;
      });
      await _clearTokens();
      return;
    }

    try {
      final success = await OAuthService.logout(
        provider,
        _tokenResponse!.idToken!,
      );

      if (success) {
        setState(() {
          _tokenResponse = null;
        });
        await _clearTokens();
      } else {
        throw Exception('Logout failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AuthWebView Example'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_tokenResponse == null) ...[
              const Text(
                'Choose a provider to login:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ..._providers.map(
                (provider) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ElevatedButton(
                    onPressed: () => _login(provider),
                    child: Text('Login with ${provider.name}'),
                  ),
                ),
              ),
            ] else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Authentication Successful!',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Access Token: ${_tokenResponse!.accessToken}'),
                      if (_tokenResponse!.refreshToken != null) ...[
                        const SizedBox(height: 10),
                        Text('Refresh Token: ${_tokenResponse!.refreshToken}'),
                      ],
                      if (_tokenResponse!.accessTokenExpirationDateTime !=
                          null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Expires: ${_tokenResponse!.accessTokenExpirationDateTime}',
                        ),
                      ],
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => _logout(_providers.first),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onError,
                        ),
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

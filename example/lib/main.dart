import 'package:authwebview/authwebview.dart';
import 'package:flutter/material.dart';

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
        primarySwatch: Colors.blue,
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

  static const googleDiscoveryUrl =
      "https://accounts.google.com/.well-known/openid-configuration";
  static const googleClientId =
      "286942216621-6brkljrldsf6c3hjc6p1vqehaltuaun0.apps.googleusercontent.com";
  static const googleRedirectUrl = "com.example.njktest2:/oauth2redirect";
  final List<OAuthProvider> _providers = [
    const OAuthProvider(
        name: "Google",
        discoveryUrl: googleDiscoveryUrl,
        clientId: googleClientId,
        redirectUrl: googleRedirectUrl)
  ];

  Future<void> _login(OAuthProvider provider) async {
    final result = await AuthService.performOAuthFlow(
      context,
      provider,
      loadingWidget: const Center(child: CircularProgressIndicator()),
    );

    setState(() {
      _tokenResponse = result;
    });
  }

  Future<void> _logout(OAuthProvider provider, String idTokenHint) async {
    final success = await AuthService.logout(provider, idTokenHint);
    if (success) {
      setState(() {
        _tokenResponse = null;
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logout failed')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AuthWebView Example'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (_tokenResponse == null)
              ..._providers.map(
                (provider) => ElevatedButton(
                  onPressed: () => _login(provider),
                  child: Text('Login with ${provider.name}'),
                ),
              )
            else
              Column(
                children: [
                  const Text('Logged in successfully!'),
                  const SizedBox(height: 10),
                  Text('Access Token: ${_tokenResponse!.accessToken}'),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => _logout(
                        _providers.first,
                        _tokenResponse!
                            .idToken!), // Using the first provider for logout
                    child: const Text('Logout'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

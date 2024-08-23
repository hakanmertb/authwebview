class OAuthProvider {
  final String name;
  final String discoveryUrl;
  final String clientId;
  final String redirectUrl;
  final List<String> scopes;

  const OAuthProvider({
    required this.name,
    required this.discoveryUrl,
    required this.clientId,
    required this.redirectUrl,
    this.scopes = const ['openid', 'profile', 'email'],
  });
}

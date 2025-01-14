class AuthorizationTokenResponse {
  final String? accessToken;
  final String? refreshToken;
  final DateTime? accessTokenExpirationDateTime;
  final String? idToken;
  final String? tokenType;
  final List<String>? scopes;
  final Map<String, dynamic>? authorizationAdditionalParameters;

  AuthorizationTokenResponse({
    this.accessToken,
    this.refreshToken,
    this.accessTokenExpirationDateTime,
    this.idToken,
    this.tokenType,
    this.scopes,
    this.authorizationAdditionalParameters,
  });

  factory AuthorizationTokenResponse.fromJson(Map<String, dynamic> json) {
    return AuthorizationTokenResponse(
      accessToken: json['access_token'],
      refreshToken: json['refresh_token'],
      accessTokenExpirationDateTime: json['expires_in'] != null
          ? DateTime.now().add(Duration(seconds: json['expires_in']))
          : null,
      idToken: json['id_token'],
      tokenType: json['token_type'],
      scopes: json['scope']?.split(' '),
      authorizationAdditionalParameters: json,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'expires_in':
          accessTokenExpirationDateTime?.difference(DateTime.now()).inSeconds,
      'id_token': idToken,
      'token_type': tokenType,
      'scope': scopes?.join(' '),
      ...?authorizationAdditionalParameters,
    };
  }
}

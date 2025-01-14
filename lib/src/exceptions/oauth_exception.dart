class OAuthException implements Exception {
  final String message;
  final String? code;
  final String? description;
  final dynamic originalError;

  const OAuthException({
    required this.message,
    this.code,
    this.description,
    this.originalError,
  });

  @override
  String toString() {
    final buffer = StringBuffer('OAuthException: $message');
    if (code != null) buffer.write(' (Code: $code)');
    if (description != null) buffer.write('\nDescription: $description');
    if (originalError != null) buffer.write('\nOriginal error: $originalError');
    return buffer.toString();
  }

  /// Factory constructor for creating an OAuthException from an OAuth error response
  factory OAuthException.fromOAuthError(Map<String, String> errorParams) {
    return OAuthException(
      message: errorParams['error'] ?? 'Unknown OAuth error',
      description: errorParams['error_description'],
      code: errorParams['error_uri'],
    );
  }
}
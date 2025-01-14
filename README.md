# AuthWebView

A Flutter package for handling OAuth authentication flow within a webview. This package was originally developed for use at [Rapider.ai](https://www.rapider.ai) and is now available as an open-source solution for the Flutter community.

## Features

- Supports OAuth 2.0 authentication flow with PKCE
- Customizable OAuth providers
- Built-in security best practices
- Secure token storage
- Handles authorization code exchange for access token
- Provides a simple and intuitive API
- Customizable loading widget during authentication process
- Error handling and callbacks for authentication errors
- Production-tested at Rapider.ai

## Getting Started

### Prerequisites

- Flutter SDK installed
- A Flutter project setup

### Installation

Add the following to your `pubspec.yaml` file:

```yaml
dependencies:
  authwebview: ^1.0.4
```

Then run `flutter pub get` to install the package.

### Usage

Import the package in your Dart code:

```dart
import 'package:authwebview/authwebview.dart';
```

Define an OAuth provider:

```dart
final provider = OAuthProvider(
  name: 'Google',
  discoveryUrl: 'https://accounts.google.com/.well-known/openid-configuration',
  clientId: 'your-client-id',
  redirectUrl: 'your-redirect-url',
  scopes: ['openid', 'profile', 'email'],
);
```

Perform the OAuth flow:

```dart
final result = await OAuthService.performOAuthFlow(
  context,
  provider,
  loadingWidget: CircularProgressIndicator(),
);

if (result != null) {
  // Authentication successful, access tokens are available in the result
  print(result.accessToken);
} else {
  // Authentication failed or canceled by the user
}
```

Handle authentication errors:

```dart
final result = await OAuthService.performOAuthFlow(
  context,
  provider,
  loadingWidget: CircularProgressIndicator(),
  onError: (error) {
    // Handle authentication errors
    print('Authentication error: $error');
  },
);
```

## Security Best Practices

### PKCE Implementation
This package implements PKCE (Proof Key for Code Exchange) by default for enhanced security. PKCE prevents authorization code interception attacks.

### Token Storage
- Never store tokens in SharedPreferences or local storage without encryption
- Use Flutter Secure Storage or platform-specific secure storage solutions
- Implement token refresh mechanisms properly

### WebView Security
- Always verify redirect URLs
- Implement proper state validation
- Clear WebView cache and cookies after logout

### Additional Recommendations
- Implement proper SSL/TLS certificate validation
- Use appropriate timeout values
- Implement rate limiting for token refresh
- Regular security audits of implementation

## API Reference

### OAuthProvider

Represents an OAuth provider configuration.

| Property      | Type         | Description                                                 |
| ------------- | ------------ | ----------------------------------------------------------- |
| name          | String       | The name of the OAuth provider.                            |
| discoveryUrl  | String       | The URL to the provider's OpenID Connect discovery document.|
| clientId      | String       | The client ID for the OAuth application.                   |
| redirectUrl   | String       | The redirect URL for the OAuth application.                |
| scopes        | List<String> | The list of scopes to request during authentication.       |

### AuthService

Provides methods for performing the OAuth authentication flow.

| Method            | Description                                                 |
| ----------------- | ----------------------------------------------------------- |
| performOAuthFlow  | Starts the OAuth authentication flow within a webview.      |
| logout            | Performs the logout process for the authenticated user.     |
| getAuthorizationUrl | Retrieves the authorization URL for the OAuth provider.   |
| handleRedirect    | Handles the redirect URL after a successful authentication. |

### AuthorizationTokenResponse

Represents the response containing the authorization tokens.

| Property                           | Type         | Description                                          |
| ---------------------------------- | ------------ | ---------------------------------------------------- |
| accessToken                        | String?      | The access token for making authenticated requests. |
| refreshToken                       | String?      | The refresh token for obtaining a new access token.  |
| accessTokenExpirationDateTime      | DateTime?    | The expiration date and time of the access token.   |
| idToken                            | String?      | The ID token containing user information.           |
| tokenType                          | String?      | The type of the access token (e.g., Bearer).        |
| scopes                             | List<String>?| The list of scopes granted with the access token.   |
| authorizationAdditionalParameters  | Map<String, dynamic>? | Additional parameters returned with the tokens.   |

## Error Handling

The package provides error handling through custom exceptions and the `onError` callback in the `performOAuthFlow` method:

```dart
try {
  final result = await OAuthService.performOAuthFlow(
    context,
    provider,
    onError: (error) {
      print('Authentication error: $error');
    },
  );
} catch (e) {
  if (e is OAuthException) {
    print('OAuth Error: ${e.message}');
    print('Error Code: ${e.code}');
  }
}
```

## Example

A complete example application demonstrating the usage of this package can be found in the [example](example) directory.

## Contributing

Contributions are welcome! If you find a bug or want to add a feature, please create an issue or submit a pull request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
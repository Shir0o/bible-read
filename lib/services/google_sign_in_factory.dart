import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// Creates a [GoogleSignIn] instance that is configured for each platform.
GoogleSignIn createGoogleSignIn() {
  const scopes = <String>['email'];

  if (kIsWeb) {
    return GoogleSignIn(scopes: scopes);
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return GoogleSignIn(
        scopes: scopes,
        serverClientId: _androidServerClientId,
      );
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return GoogleSignIn(
        scopes: scopes,
        clientId: _appleClientId,
      );
    default:
      return GoogleSignIn(scopes: scopes);
  }
}

const String _androidServerClientId =
    '82330382748-nc1qi3kopth6dlooblaur6ldg6sd81ci.apps.googleusercontent.com';

const String _appleClientId =
    '82330382748-kv8cr6ehdtjglo5v2iqa6e8ge038kh0s.apps.googleusercontent.com';

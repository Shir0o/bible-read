import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

GoogleSignIn? _googleSignIn;

/// Returns a configured [GoogleSignIn] instance.
GoogleSignIn createGoogleSignIn() {
  if (_googleSignIn != null) {
    return _googleSignIn!;
  }

  const scopes = <String>['email'];

  if (kIsWeb) {
    _googleSignIn = GoogleSignIn(scopes: scopes);
    return _googleSignIn!;
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      _googleSignIn = GoogleSignIn(
        scopes: scopes,
        serverClientId: _androidServerClientId,
      );
      break;
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      _googleSignIn = GoogleSignIn(
        scopes: scopes,
        clientId: _appleClientId,
      );
      break;
    default:
      _googleSignIn = GoogleSignIn(scopes: scopes);
  }

  return _googleSignIn!;
}

const String _androidServerClientId =
    '82330382748-nc1qi3kopth6dlooblaur6ldg6sd81ci.apps.googleusercontent.com';

const String _appleClientId =
    '82330382748-kv8cr6ehdtjglo5v2iqa6e8ge038kh0s.apps.googleusercontent.com';

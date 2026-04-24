import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

bool _googleSignInInitialized = false;

/// Returns a configured [GoogleSignIn] instance.
GoogleSignIn createGoogleSignIn() {
  final instance = GoogleSignIn.instance;

  if (_googleSignInInitialized) {
    return instance;
  }

  // Configuration is handled via initialize() in the latest version.
  // We'll call it here, but it's async, so we'll return the instance
  // and assume it's being initialized or will be initialized.
  // Ideally, initialize() should be called at app startup.
  _initializeGoogleSignIn();

  return instance;
}

Future<void> _initializeGoogleSignIn() async {
  if (_googleSignInInitialized) return;

  String? clientId;
  String? serverClientId;

  if (!kIsWeb) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        serverClientId = _androidServerClientId;
        break;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        clientId = _appleClientId;
        break;
      default:
        break;
    }
  }

  await GoogleSignIn.instance.initialize(
    clientId: clientId,
    serverClientId: serverClientId,
  );
  _googleSignInInitialized = true;
}

const String _androidServerClientId =
    '82330382748-nc1qi3kopth6dlooblaur6ldg6sd81ci.apps.googleusercontent.com';

const String _appleClientId =
    '82330382748-kv8cr6ehdtjglo5v2iqa6e8ge038kh0s.apps.googleusercontent.com';

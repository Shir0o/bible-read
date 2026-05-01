import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

bool _initialized = false;
Future<void>? _initializing;
StreamSubscription<GoogleSignInAuthenticationEvent>? _eventsSubscription;
FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

/// Initializes Google Sign-In and bridges its authentication events to
/// Firebase. Call once at app startup, after `Firebase.initializeApp()`.
///
/// On startup this also kicks off `attemptLightweightAuthentication()` so a
/// returning user is silently signed in without tapping the button again.
/// Subsequent calls are no-ops.
Future<void> initializeGoogleSignIn({FirebaseAuth? firebaseAuth}) {
  if (firebaseAuth != null) _firebaseAuth = firebaseAuth;
  if (_initialized) return Future<void>.value();
  return _initializing ??= _doInitialize();
}

Future<void> _doInitialize() async {
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

  _eventsSubscription ??= GoogleSignIn.instance.authenticationEvents.listen(
    _onAuthenticationEvent,
    onError: (Object error) {
      if (kDebugMode) {
        debugPrint('GoogleSignIn auth event error: $error');
      }
    },
  );

  _initialized = true;

  unawaited(_attemptSilentSignIn());
}

Future<void> _attemptSilentSignIn() async {
  try {
    await GoogleSignIn.instance.attemptLightweightAuthentication();
  } catch (error) {
    if (kDebugMode) {
      debugPrint('Lightweight Google sign-in failed: $error');
    }
  }
}

Future<void> _onAuthenticationEvent(
    GoogleSignInAuthenticationEvent event) async {
  if (event is! GoogleSignInAuthenticationEventSignIn) return;
  final account = event.user;
  final idToken = account.authentication.idToken;
  if (idToken == null) return;

  final current = _firebaseAuth.currentUser;
  if (current != null) {
    final isGoogleProvider =
        current.providerData.any((p) => p.providerId == 'google.com');
    if (isGoogleProvider && current.email == account.email) {
      return;
    }
  }

  try {
    await _firebaseAuth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
  } catch (error) {
    if (kDebugMode) {
      debugPrint('Firebase sign-in from Google event failed: $error');
    }
  }
}

/// Returns the configured singleton [GoogleSignIn]. Initialization is normally
/// done at app startup via [initializeGoogleSignIn]; this triggers it lazily
/// as a safety net for legacy callers and tests.
GoogleSignIn createGoogleSignIn() {
  if (!_initialized && _initializing == null) {
    unawaited(initializeGoogleSignIn());
  }
  return GoogleSignIn.instance;
}

@visibleForTesting
Future<void> resetGoogleSignInForTest() async {
  await _eventsSubscription?.cancel();
  _eventsSubscription = null;
  _initialized = false;
  _initializing = null;
  _firebaseAuth = FirebaseAuth.instance;
}

const String _androidServerClientId =
    '82330382748-nc1qi3kopth6dlooblaur6ldg6sd81ci.apps.googleusercontent.com';

const String _appleClientId =
    '82330382748-kv8cr6ehdtjglo5v2iqa6e8ge038kh0s.apps.googleusercontent.com';

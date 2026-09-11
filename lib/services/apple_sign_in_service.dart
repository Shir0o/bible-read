import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'error_logger.dart';

/// Service abstraction for Apple Sign-In authentication.
abstract class AppleSignInService {
  /// Returns true if Apple Sign-In is supported on the current platform.
  bool get isSupported;

  /// Performs Apple authentication, exchanges credentials with Firebase,
  /// updates user display name if provided by Apple, and returns the [UserCredential].
  ///
  /// Returns `null` if the user cancels authorization.
  Future<UserCredential?> signIn();
}

/// Default production implementation of [AppleSignInService].
class DefaultAppleSignInService implements AppleSignInService {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  DefaultAppleSignInService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance;

  @override
  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isMacOS;
  }

  /// Generates a cryptographically secure random string of 32 characters.
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  /// Returns the sha256 of an input string.
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  @override
  Future<UserCredential?> signIn() async {
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);

    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final oauthProvider = OAuthProvider('apple.com');
      final authCredential = oauthProvider.credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      final userCredential = await auth.signInWithCredential(authCredential);
      final user = userCredential.user;

      if (user != null) {
        // Apple only provides user fullName on the very first sign-in request.
        final givenName = appleCredential.givenName ?? '';
        final familyName = appleCredential.familyName ?? '';
        final fullName = '$givenName $familyName'.trim();

        if (fullName.isNotEmpty) {
          if (user.displayName == null || user.displayName!.isEmpty) {
            await user.updateDisplayName(fullName);
          }
          await firestore.collection('users').doc(user.uid).set({
            'displayName': fullName,
            if (user.email != null) 'email': user.email,
          }, SetOptions(merge: true));
        }
      }

      return userCredential;
    } catch (error, st) {
      if (error is SignInWithAppleAuthorizationException) {
        if (error.code == AuthorizationErrorCode.canceled) {
          // User tapped Cancel in native modal; return null without error
          return null;
        }
      }
      if (kDebugMode) {
        debugPrint('Sign in with Apple failed: $error');
      }
      ErrorLogger.log(error, st);
      rethrow;
    }
  }
}

import 'dart:async';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakeGoogleSignInPlatform extends GoogleSignInPlatform
    with MockPlatformInterfaceMixin {
  GoogleSignInUserData? user;
  int silentSignInCount = 0;
  bool signInCalled = false;
  bool signOutCalled = false;
  bool disconnectCalled = false;
  Exception? signInError;

  FakeGoogleSignInPlatform({this.user, this.signInError});

  @override
  Future<void> init(InitParameters params) async {}

  @override
  Future<AuthenticationResults?> attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) async {
    silentSignInCount++;
    if (signInError != null) throw signInError!;
    if (user == null) return null;
    return AuthenticationResults(
      user: user!,
      authenticationTokens: const AuthenticationTokenData(idToken: 'idToken'),
    );
  }

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async {
    signInCalled = true;
    if (signInError != null) throw signInError!;
    if (user == null) {
      throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
        description: 'Sign in cancelled',
      );
    }
    return AuthenticationResults(
      user: user!,
      authenticationTokens: const AuthenticationTokenData(idToken: 'idToken'),
    );
  }

  @override
  Future<void> signOut(SignOutParams params) async {
    signOutCalled = true;
  }

  @override
  Future<void> disconnect(DisconnectParams params) async {
    disconnectCalled = true;
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  bool authorizationRequiresUserInteraction() => true;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async {
    return const ClientAuthorizationTokenData(accessToken: 'accessToken');
  }

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async {
    return const ServerAuthorizationTokenData(serverAuthCode: 'serverAuthCode');
  }

  @override
  Stream<AuthenticationEvent>? get authenticationEvents => null;

  @override
  Future<void> clearAuthorizationToken(
    ClearAuthorizationTokenParams params,
  ) async {}
}

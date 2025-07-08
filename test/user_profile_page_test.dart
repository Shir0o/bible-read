// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import "package:firebase_auth/firebase_auth.dart";
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/user_profile_page.dart';

class FakeGoogleSignInPlatform extends GoogleSignInPlatform {
  FakeGoogleSignInPlatform({this.userData, this.signInError});

  GoogleSignInUserData? userData;
  Exception? signInError;
  bool signInCalled = false;
  bool getTokensCalled = false;

  @override
  bool get isMock => true;

  @override
  Future<void> init(
      {List<String> scopes = const <String>[],
      SignInOption signInOption = SignInOption.standard,
      String? hostedDomain,
      String? clientId}) async {}

  @override
  Future<GoogleSignInUserData?> signIn() async {
    signInCalled = true;
    if (signInError != null) {
      throw signInError!;
    }
    return userData;
  }

  @override
  Future<GoogleSignInTokenData> getTokens(
      {required String email, bool? shouldRecoverAuth}) async {
    getTokensCalled = true;
    return GoogleSignInTokenData(idToken: 'id', accessToken: 'access');
  }
}

class TrackingAuth extends MockFirebaseAuth {
  bool signInCalled = false;
  AuthCredential? receivedCredential;

  @override
  Future<UserCredential> signInWithCredential(AuthCredential? credential) {
    signInCalled = true;
    receivedCredential = credential;
    return super.signInWithCredential(credential);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('shows loading then sign in button', (tester) async {
    await tester.pumpWidget(MaterialApp(home: UserProfilePage()));

    // Initially loading indicator
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('successful sign in navigates to main page', (tester) async {
    final googlePlatform = FakeGoogleSignInPlatform(
      userData: GoogleSignInUserData(email: 'e', id: 'id', displayName: 'd'),
    );
    GoogleSignInPlatform.instance = googlePlatform;
    final auth = TrackingAuth();

    await tester.pumpWidget(
      MaterialApp(home: UserProfilePage(auth: auth)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();

    expect(googlePlatform.signInCalled, isTrue);
    expect(auth.signInCalled, isTrue);
    expect(find.byType(MainPage), findsOneWidget);
  });

  testWidgets('sign in cancelled shows snackbar', (tester) async {
    final googlePlatform = FakeGoogleSignInPlatform(userData: null);
    GoogleSignInPlatform.instance = googlePlatform;
    final auth = TrackingAuth();

    await tester.pumpWidget(MaterialApp(home: UserProfilePage(auth: auth)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in with Google'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Sign in cancelled'), findsOneWidget);
    expect(auth.signInCalled, isFalse);
  });

  testWidgets('sign in failure shows snackbar', (tester) async {
    final googlePlatform =
        FakeGoogleSignInPlatform(signInError: Exception('fail'));
    GoogleSignInPlatform.instance = googlePlatform;
    final auth = TrackingAuth();

    await tester.pumpWidget(MaterialApp(home: UserProfilePage(auth: auth)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in with Google'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Sign in failed'), findsOneWidget);
    expect(auth.signInCalled, isFalse);
  });
}

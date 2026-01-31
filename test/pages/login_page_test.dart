import 'package:bible_read/pages/login_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_mocks/google_sign_in_mocks.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecordingAuth extends MockFirebaseAuth {
  bool signInCalled = false;
  String? email;
  String? password;
  bool signInWithCredentialCalled = false;

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    signInCalled = true;
    this.email = email;
    this.password = password;
    return super.signInWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential? credential) {
    signInWithCredentialCalled = true;
    return super.signInWithCredential(credential);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('LoginPage', () {
    testWidgets('signs in with email and navigates to MainPage',
        (tester) async {
      await mockNetworkImagesFor(() async {
        final auth = RecordingAuth();
        SharedPreferences.setMockInitialValues({});

        await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));

        await tester.enterText(
            find.byKey(const Key('loginEmailField')), 'user@example.com');
        await tester.enterText(
            find.byKey(const Key('loginPasswordField')), 'pw');
        // Button text is 'Login' in new UI
        await tester.tap(find.text('Login'));
        await tester.pumpAndSettle();

        expect(auth.signInCalled, isTrue);
        expect(auth.email, 'user@example.com');
        expect(auth.password, 'pw');
        expect(find.byType(MainPage), findsOneWidget);
      });
    });

    testWidgets('signs in with Google and navigates to MainPage',
        (tester) async {
      await mockNetworkImagesFor(() async {
        final auth = RecordingAuth();
        final googleSignIn = MockGoogleSignIn();
        SharedPreferences.setMockInitialValues({});

        await tester.pumpWidget(MaterialApp(
          home: LoginPage(
            auth: auth,
            googleSignInProvider: () => googleSignIn,
          ),
        ));

        await tester.tap(find.text('Sign in with Google'));
        // Trigger the async gap
        await tester.pump();

        expect(auth.signInWithCredentialCalled, isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(MainPage), findsOneWidget);
      });
    });

    testWidgets('toggles password visibility', (tester) async {
      await mockNetworkImagesFor(() async {
        final auth = RecordingAuth();
        await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));

        final passwordFieldFinder = find.byKey(const Key('loginPasswordField'));
        // Find the icon button inside the password field
        final toggleButtonFinder = find.descendant(
          of: passwordFieldFinder,
          matching: find.byType(IconButton),
        );

        // Helper to check obscure text
        bool isObscured() {
          final textField = find.descendant(
            of: passwordFieldFinder,
            matching: find.byType(TextField),
          );
          return tester.widget<TextField>(textField).obscureText;
        }

        // Initial state: obscured
        expect(isObscured(), isTrue);

        // Verify semantics
        var semantics = tester.getSemantics(toggleButtonFinder);
        var data = semantics.getSemanticsData();
        expect(data.tooltip, 'Show password');
        expect(data.hasFlag(SemanticsFlag.isButton), isTrue);

        // Tap to show
        await tester.tap(toggleButtonFinder);
        await tester.pump();

        // State: visible
        expect(isObscured(), isFalse);
        semantics = tester.getSemantics(toggleButtonFinder);
        data = semantics.getSemanticsData();
        expect(data.tooltip, 'Hide password');

        // Tap to hide
        await tester.tap(toggleButtonFinder);
        await tester.pump();

        // State: obscured
        expect(isObscured(), isTrue);
      });
    });
  });
}

import 'package:bible_read/pages/login_page.dart';
import 'package:bible_read/pages/signup_page.dart';
import 'package:bible_read/services/error_logger.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/fake_google_sign_in_platform.dart';

class MockVibrationService extends Mock implements VibrationService {}

class RecordingAuth extends MockFirebaseAuth {
  bool signInCalled = false;
  String? email;
  String? password;
  bool signInWithCredentialCalled = false;
  bool sendPasswordResetEmailCalled = false;
  String? resetEmail;
  Exception? errorOnSignIn;

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    signInCalled = true;
    this.email = email;
    this.password = password;
    if (errorOnSignIn != null) {
      return Future.error(errorOnSignIn!);
    }
    return super.signInWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential? credential) {
    signInWithCredentialCalled = true;
    return super.signInWithCredential(credential);
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    sendPasswordResetEmailCalled = true;
    resetEmail = email;
    await Future.delayed(const Duration(milliseconds: 10));
    return super.sendPasswordResetEmail(
      email: email,
      actionCodeSettings: actionCodeSettings,
    );
  }
}

class TestMainPage extends StatelessWidget {
  const TestMainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Text('Test Main Page'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
    ErrorLogger.muteForTest = true;
  });

  setUp(() {
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform(
      user: const GoogleSignInUserData(
        id: 'google_user_id',
        email: 'gmail.user@example.com',
        displayName: 'Gmail User',
      ),
    );
  });

  group('LoginPage', () {
    testWidgets('signs in with email and navigates to MainPage', (
      tester,
    ) async {
      await mockNetworkImagesFor(() async {
        final auth = RecordingAuth();
        SharedPreferences.setMockInitialValues({});

        await tester.pumpWidget(
          MaterialApp(
            home: LoginPage(
              auth: auth,
              mainPageBuilder: (_) => const TestMainPage(),
            ),
          ),
        );

        await tester.enterText(
          find.byKey(const Key('loginEmailField')),
          'user@my-company.com',
        );
        await tester.enterText(
          find.byKey(const Key('loginPasswordField')),
          'pw',
        );
        // Button text is 'Login' in new UI
        await tester.tap(find.text('Login'));
        await tester.pumpAndSettle();

        expect(auth.signInCalled, isTrue);
        expect(auth.email, 'user@my-company.com');
        expect(auth.password, 'pw');
        expect(find.byType(TestMainPage), findsOneWidget);
      });
    });

    testWidgets('signs in with Google and navigates to MainPage', (
      tester,
    ) async {
      await mockNetworkImagesFor(() async {
        final auth = RecordingAuth();
        SharedPreferences.setMockInitialValues({});

        await tester.pumpWidget(
          MaterialApp(
            home: LoginPage(
              auth: auth,
              googleSignInProvider: () => GoogleSignIn.instance,
              mainPageBuilder: (_) => const TestMainPage(),
            ),
          ),
        );

        final googleButton = find.text('Continue with Google');
        await tester.ensureVisible(googleButton);
        await tester.tap(googleButton);
        // Trigger the async gap
        await tester.pump();

        expect(auth.signInWithCredentialCalled, isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(TestMainPage), findsOneWidget);
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
        // ignore: deprecated_member_use
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

    testWidgets('shows error snackbar on sign in failure', (tester) async {
      await mockNetworkImagesFor(() async {
        final auth = RecordingAuth();
        auth.errorOnSignIn = FirebaseAuthException(code: 'user-not-found');

        await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));

        await tester.enterText(
          find.byKey(const Key('loginEmailField')),
          'fail@test.com',
        );
        await tester.enterText(
          find.byKey(const Key('loginPasswordField')),
          'wrong',
        );
        await tester.tap(find.text('Login'));
        await tester.pump(); // Start future
        await tester.pump(); // Resolve future (error)

        // Wait for snackbar animation
        await tester.pumpAndSettle();

        expect(
          find.widgetWithText(
            SnackBar,
            'Failed to sign in. Please check credentials.',
          ),
          findsOneWidget,
        );
        expect(auth.signInCalled, isTrue);
      });
    });

    testWidgets('shows error when fields are empty', (tester) async {
      await mockNetworkImagesFor(() async {
        final auth = RecordingAuth();
        await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));

        // Tap login without entering anything
        await tester.tap(find.text('Login'));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('Please fill in all fields'), findsAtLeast(1));
        expect(
          find.widgetWithText(SnackBar, 'Please fill in all fields'),
          findsOneWidget,
        );
        expect(auth.signInCalled, isFalse);
      });
    });

    testWidgets('shows error when email is invalid', (tester) async {
      await mockNetworkImagesFor(() async {
        final auth = RecordingAuth();
        await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));

        await tester.enterText(
          find.byKey(const Key('loginEmailField')),
          'invalid-email',
        );
        await tester.enterText(
          find.byKey(const Key('loginPasswordField')),
          'password',
        );
        await tester.tap(find.text('Login'));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
            find.text('Please enter a valid email address'), findsAtLeast(1));
        expect(
          find.widgetWithText(SnackBar, 'Please enter a valid email address'),
          findsOneWidget,
        );
        expect(auth.signInCalled, isFalse);
      });
    });

    testWidgets('dynamic email clear button appears and clears input',
        (tester) async {
      await mockNetworkImagesFor(() async {
        final auth = RecordingAuth();
        await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));

        final emailFieldFinder = find.byKey(const Key('loginEmailField'));

        // Initially no clear button
        expect(
            find.descendant(
              of: emailFieldFinder,
              matching: find.byIcon(Icons.clear),
            ),
            findsNothing);

        // Enter some text
        await tester.enterText(emailFieldFinder, 'some-text');
        await tester.pump();

        // Clear button should now appear
        final clearButtonFinder = find.descendant(
          of: emailFieldFinder,
          matching: find.byIcon(Icons.clear),
        );
        expect(clearButtonFinder, findsOneWidget);

        // Tap clear button
        await tester.tap(clearButtonFinder);
        await tester.pump();

        // Email field should be empty, and clear button should be gone
        final textField = find.descendant(
          of: emailFieldFinder,
          matching: find.byType(TextField),
        );
        expect(tester.widget<TextField>(textField).controller?.text, isEmpty);
        expect(
            find.descendant(
              of: emailFieldFinder,
              matching: find.byIcon(Icons.clear),
            ),
            findsNothing);
      });
    });

    testWidgets('verifies semantics for Forgot Password and Sign up links', (
      tester,
    ) async {
      await mockNetworkImagesFor(() async {
        final auth = RecordingAuth();
        await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));

        final forgotPasswordFinder = find.byKey(
          const Key('forgotPasswordSemantics'),
        );
        final signUpFinder = find.byKey(const Key('signUpSemantics'));

        // Verify Forgot Password semantics
        final forgotPasswordSemantics = tester.getSemantics(
          forgotPasswordFinder,
        );
        final forgotPasswordData = forgotPasswordSemantics.getSemanticsData();
        // ignore: deprecated_member_use
        expect(forgotPasswordData.hasFlag(SemanticsFlag.isButton), isTrue);
        expect(forgotPasswordData.label, 'Forgot password');

        // Verify Sign up semantics
        final signUpSemantics = tester.getSemantics(signUpFinder);
        final signUpData = signUpSemantics.getSemanticsData();
        // ignore: deprecated_member_use
        expect(signUpData.hasFlag(SemanticsFlag.isButton), isTrue);
        expect(signUpData.label, 'Sign up');

        // Verify Sign up navigation
        await tester.ensureVisible(signUpFinder);
        await tester.tap(signUpFinder);
        await tester.pumpAndSettle();

        expect(find.byType(SignupPage), findsOneWidget);
      });
    });

    testWidgets('allows user to reset password', (tester) async {
      await mockNetworkImagesFor(() async {
        final auth = RecordingAuth();
        final vibrationService = MockVibrationService();
        when(() => vibrationService.mediumImpact()).thenAnswer((_) async {});
        when(() => vibrationService.lightImpact()).thenAnswer((_) async {});

        await tester.pumpWidget(
          MaterialApp(
            home: LoginPage(auth: auth, vibrationService: vibrationService),
          ),
        );

        final forgotPasswordFinder = find.byKey(
          const Key('forgotPasswordSemantics'),
        );

        // Tap Forgot Password
        await tester.ensureVisible(forgotPasswordFinder);
        await tester.tap(forgotPasswordFinder);
        await tester.pumpAndSettle();

        // Check if dialog appears
        expect(find.text('Reset Password'), findsOneWidget);

        // Enter email
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          'reset@test.com',
        );
        await tester.pump();

        // Submit via keyboard
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pump(); // Trigger setState
        await tester.pump(
          const Duration(milliseconds: 100),
        ); // Allow future to complete
        await tester.pumpAndSettle(); // Allow dialog to close

        // Verify API call
        expect(auth.sendPasswordResetEmailCalled, isTrue);
        expect(auth.resetEmail, 'reset@test.com');

        // Verify Success SnackBar
        expect(
          find.widgetWithText(SnackBar, 'Password reset email sent'),
          findsOneWidget,
        );
        // Verify haptic feedback
        verify(() => vibrationService.mediumImpact()).called(1);
        // Verify dialog closed
        expect(find.text('Reset Password'), findsNothing);
      });
    });

    testWidgets(
      'triggers heavy impact vibration on invalid email in reset dialog',
      (tester) async {
        await mockNetworkImagesFor(() async {
          final auth = RecordingAuth();
          final vibrationService = MockVibrationService();
          when(() => vibrationService.heavyImpact()).thenAnswer((_) async {});
          when(() => vibrationService.lightImpact()).thenAnswer((_) async {});

          await tester.pumpWidget(
            MaterialApp(
              home: LoginPage(auth: auth, vibrationService: vibrationService),
            ),
          );

          final forgotPasswordFinder = find.byKey(
            const Key('forgotPasswordSemantics'),
          );

          // Tap Forgot Password
          await tester.ensureVisible(forgotPasswordFinder);
          await tester.tap(forgotPasswordFinder);
          await tester.pumpAndSettle();

          // Enter invalid email
          await tester.enterText(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            ),
            'invalid-email',
          );
          await tester.pump();

          // Tap Send Link
          await tester.tap(find.text('Send Link'));
          await tester.pump();
          await tester.pumpAndSettle();

          // Verify haptic feedback
          verify(() => vibrationService.heavyImpact()).called(1);
          // Verify error SnackBar
          expect(
            find.widgetWithText(SnackBar, 'Please enter a valid email address'),
            findsOneWidget,
          );
        });
      },
    );

    testWidgets(
      'dynamic email clear button appears and clears input in forgot password dialog',
      (tester) async {
        await mockNetworkImagesFor(() async {
          final auth = RecordingAuth();
          final vibrationService = MockVibrationService();
          when(() => vibrationService.lightImpact()).thenAnswer((_) async {});

          await tester.pumpWidget(
            MaterialApp(
              home: LoginPage(auth: auth, vibrationService: vibrationService),
            ),
          );

          final forgotPasswordFinder = find.byKey(
            const Key('forgotPasswordSemantics'),
          );

          // Tap Forgot Password
          await tester.ensureVisible(forgotPasswordFinder);
          await tester.tap(forgotPasswordFinder);
          await tester.pumpAndSettle();

          final emailFieldFinder =
              find.byKey(const Key('forgotPasswordEmailField'));

          // Initially no clear button inside the text field
          expect(
            find.descendant(
              of: emailFieldFinder,
              matching: find.byIcon(Icons.clear),
            ),
            findsNothing,
          );

          // Enter text
          await tester.enterText(emailFieldFinder, 'reset-email@test.com');
          await tester.pump();

          // Clear button should appear
          final clearButtonFinder = find.descendant(
            of: emailFieldFinder,
            matching: find.byIcon(Icons.clear),
          );
          expect(clearButtonFinder, findsOneWidget);

          // Tap clear button
          await tester.tap(clearButtonFinder);
          await tester.pump();

          // Email field should be empty, and clear button should be gone
          expect(tester.widget<TextField>(emailFieldFinder).controller?.text,
              isEmpty);
          expect(
            find.descendant(
              of: emailFieldFinder,
              matching: find.byIcon(Icons.clear),
            ),
            findsNothing,
          );
        });
      },
    );
  });
}

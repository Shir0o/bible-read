import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bible_read/widgets/login_form.dart';
import 'package:bible_read/services/error_logger.dart';
import 'package:flutter/semantics.dart';

class RecordingAuth extends MockFirebaseAuth {
  bool signInCalled = false;
  String? email;
  String? password;

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
}

class FailingAuth extends MockFirebaseAuth {
  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    throw Exception('fail');
  }
}

class MockCrashlytics extends Mock implements FirebaseCrashlytics {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signs in with entered credentials and calls onComplete',
      (tester) async {
    final auth = RecordingAuth();
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginForm(
            auth: auth,
            onComplete: () => completed = true,
          ),
        ),
      ),
    );

    await tester.enterText(
        find.byKey(const Key('loginEmailField')), 'user@example.com');
    await tester.enterText(find.byKey(const Key('loginPasswordField')), 'pw');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(auth.signInCalled, isTrue);
    expect(auth.email, 'user@example.com');
    expect(auth.password, 'pw');
    expect(completed, isTrue);
  });

  testWidgets('logs error and shows snackbar when sign in fails',
      (tester) async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    final auth = FailingAuth();
    final crashlytics = MockCrashlytics();
    ErrorLogger.crashlytics = crashlytics;

    when(() => crashlytics.recordError(
          any(),
          any(),
          reason: null,
          information: const [],
          printDetails: null,
          fatal: false,
        )).thenAnswer((_) async {});

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginForm(auth: auth),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();
    });

    await tester.enterText(
        find.byKey(const Key('loginEmailField')), 'user@example.com');
    await tester.enterText(find.byKey(const Key('loginPasswordField')), 'pw');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    verify(() => crashlytics.recordError(
          any(),
          any(),
          reason: null,
          information: const [],
          printDetails: null,
          fatal: false,
        )).called(1);
    expect(find.textContaining('Failed to sign in'), findsOneWidget);
  }, skip: true);

  testWidgets('fields have correct keyboard configuration', (tester) async {
    final auth = RecordingAuth();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginForm(auth: auth),
        ),
      ),
    );

    final emailField =
        tester.widget<TextField>(find.byKey(const Key('loginEmailField')));
    expect(emailField.keyboardType, TextInputType.emailAddress);
    expect(emailField.textInputAction, TextInputAction.next);
    expect(emailField.autofillHints, contains(AutofillHints.email));

    final passwordField =
        tester.widget<TextField>(find.byKey(const Key('loginPasswordField')));
    expect(passwordField.textInputAction, TextInputAction.done);
    expect(passwordField.autofillHints, contains(AutofillHints.password));
    expect(passwordField.onSubmitted, isNotNull);

    // Test onSubmitted triggers submit
    await tester.enterText(
        find.byKey(const Key('loginEmailField')), 'test@example.com');
    await tester.enterText(find.byKey(const Key('loginPasswordField')), 'password');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(auth.signInCalled, isTrue);
  });

  testWidgets('toggles password visibility', (tester) async {
    final auth = RecordingAuth();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginForm(auth: auth),
        ),
      ),
    );

    final passwordFieldFinder = find.byKey(const Key('loginPasswordField'));
    final toggleButtonFinder = find.descendant(
      of: passwordFieldFinder,
      matching: find.byType(IconButton),
    );

    // Initial state: obscured
    expect(
      tester.widget<TextField>(passwordFieldFinder).obscureText,
      isTrue,
    );
    var semantics = tester.getSemantics(toggleButtonFinder);
    var data = semantics.getSemanticsData();
    expect(data.tooltip, 'Show password');
    expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(data.hasFlag(SemanticsFlag.isEnabled), isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);

    // Tap to show
    await tester.tap(toggleButtonFinder);
    await tester.pump();

    // State: visible
    expect(
      tester.widget<TextField>(passwordFieldFinder).obscureText,
      isFalse,
    );
    semantics = tester.getSemantics(toggleButtonFinder);
    data = semantics.getSemanticsData();
    expect(data.tooltip, 'Hide password');
    expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(data.hasFlag(SemanticsFlag.isEnabled), isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);

    // Tap to hide
    await tester.tap(toggleButtonFinder);
    await tester.pump();

    // State: obscured
    expect(
      tester.widget<TextField>(passwordFieldFinder).obscureText,
      isTrue,
    );
  });
}

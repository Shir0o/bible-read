import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/signup_form.dart';
import 'package:bible_read/widgets/success_animation.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/services/error_logger.dart';
import 'package:flutter/semantics.dart';
import '../helpers/mock_lottie_http_client.dart';

class RecordingAuth extends MockFirebaseAuth {
  bool createCalled = false;
  String? email;
  String? password;

  RecordingAuth({super.mockUser}) : super();

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    createCalled = true;
    this.email = email;
    this.password = password;
    return super
        .createUserWithEmailAndPassword(email: email, password: password);
  }
}

class FailingAuth extends MockFirebaseAuth {
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    throw Exception('fail');
  }
}

class NullUserCredential implements UserCredential {
  @override
  AdditionalUserInfo? get additionalUserInfo => null;

  @override
  AuthCredential? get credential => null;

  @override
  User? get user => null;

  @override
  String toString() => 'NullUserCredential';
}

class NullUserAuth extends MockFirebaseAuth {
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    return NullUserCredential();
  }
}

class _TestVibrationService extends VibrationService {
  const _TestVibrationService() : super();

  @override
  Future<void> tap() async {}

  @override
  Future<void> lightImpact() async {}

  @override
  Future<void> mediumImpact() async {}

  @override
  Future<void> heavyImpact() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupLottieHttpOverrides);
  tearDownAll(resetHttpOverrides);

  tearDown(() {
    ErrorLogger.resetForTest();
  });

  setUp(() {
    ErrorLogger.muteForTest = true;
  });

  const vibration = _TestVibrationService();

  testWidgets('creates account and writes user document then calls onComplete',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = RecordingAuth();
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignupForm(
            auth: auth,
            firestore: firestore,
            onComplete: () => completed = true,
            vibrationService: vibration,
          ),
        ),
      ),
    );

    await tester.enterText(
        find.byKey(const Key('signupEmailField')), 'user@example.com');
    await tester.enterText(find.byKey(const Key('signupPasswordField')), 'pw');
    await tester.enterText(find.byKey(const Key('signupConfirmField')), 'pw');
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(auth.createCalled, isTrue);
    expect(auth.email, 'user@example.com');
    expect(auth.password, 'pw');
    final uid = auth.currentUser!.uid;
    final displayName = auth.currentUser!.displayName ?? '';
    final doc = await firestore.collection('users').doc(uid).get();
    expect(doc.exists, isTrue);
    expect(doc.data()?['name'], displayName);
    expect(doc.data()?['email'], 'user@example.com');
    expect(completed, isTrue);
    expect(find.byType(SuccessAnimation), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    addTearDown(() async {
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();
    });
  });

  testWidgets('shows snackbar when passwords do not match', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = RecordingAuth();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignupForm(
            auth: auth,
            firestore: firestore,
            vibrationService: vibration,
          ),
        ),
      ),
    );

    await tester.enterText(
        find.byKey(const Key('signupEmailField')), 'user@example.com');
    await tester.enterText(find.byKey(const Key('signupPasswordField')), 'pw1');
    await tester.enterText(find.byKey(const Key('signupConfirmField')), 'pw2');
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(auth.createCalled, isFalse);
    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('shows error snackbar when sign up fails', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = FailingAuth();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignupForm(
            auth: auth,
            firestore: firestore,
            vibrationService: vibration,
          ),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();
    });

    await tester.enterText(
        find.byKey(const Key('signupEmailField')), 'user@example.com');
    await tester.enterText(find.byKey(const Key('signupPasswordField')), 'pw');
    await tester.enterText(find.byKey(const Key('signupConfirmField')), 'pw');
    await tester.runAsync(() async {
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      tester.takeException();
    });
    expect(find.text('Failed to sign up. Please try again.'), findsOneWidget);
  });

  testWidgets('shows error snackbar when auth returns null user',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = NullUserAuth();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignupForm(
            auth: auth,
            firestore: firestore,
            vibrationService: vibration,
          ),
        ),
      ),
    );
    tester.takeException(); // Clear any leftovers
    await tester.enterText(
        find.byKey(const Key('signupEmailField')), 'user@example.com');
    await tester.enterText(find.byKey(const Key('signupPasswordField')), 'pw');
    await tester.enterText(find.byKey(const Key('signupConfirmField')), 'pw');
    await tester.runAsync(() async {
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      tester.takeException();
    });
    expect(find.text('Failed to sign up. Please try again.'), findsOneWidget);
  });

  testWidgets('toggles password visibility for both fields', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = RecordingAuth();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignupForm(
            auth: auth,
            firestore: firestore,
            vibrationService: vibration,
          ),
        ),
      ),
    );

    // Password Field
    final passwordFieldFinder = find.byKey(const Key('signupPasswordField'));
    final passwordToggleFinder = find.descendant(
      of: passwordFieldFinder,
      matching: find.byType(IconButton),
    );

    // Initial state
    expect(tester.widget<TextField>(passwordFieldFinder).obscureText, isTrue);
    var semantics = tester.getSemantics(passwordToggleFinder);
    var data = semantics.getSemanticsData();
    expect(data.tooltip, 'Show password');
    expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(data.hasFlag(SemanticsFlag.isEnabled), isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);

    // Toggle on
    await tester.tap(passwordToggleFinder);
    await tester.pump();
    expect(tester.widget<TextField>(passwordFieldFinder).obscureText, isFalse);
    semantics = tester.getSemantics(passwordToggleFinder);
    data = semantics.getSemanticsData();
    expect(data.tooltip, 'Hide password');
    expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(data.hasFlag(SemanticsFlag.isEnabled), isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);

    // Confirm Field
    final confirmFieldFinder = find.byKey(const Key('signupConfirmField'));
    final confirmToggleFinder = find.descendant(
      of: confirmFieldFinder,
      matching: find.byType(IconButton),
    );

    // Initial state
    expect(tester.widget<TextField>(confirmFieldFinder).obscureText, isTrue);

    // Toggle on
    await tester.tap(confirmToggleFinder);
    await tester.pump();
    expect(tester.widget<TextField>(confirmFieldFinder).obscureText, isFalse);

    // Ensure independent toggling: Toggle password off, confirm should stay on
    await tester.tap(passwordToggleFinder);
    await tester.pump();
    expect(tester.widget<TextField>(passwordFieldFinder).obscureText, isTrue);
    expect(tester.widget<TextField>(confirmFieldFinder).obscureText, isFalse);
  });
}

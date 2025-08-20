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
}

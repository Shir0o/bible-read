import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/signup_form.dart';
import 'package:bible_read/widgets/success_animation.dart';
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
  }) {
    throw Exception('fail');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupLottieHttpOverrides);
  tearDownAll(resetHttpOverrides);

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
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Failed to sign up. Please try again.'), findsOneWidget);
  });
}

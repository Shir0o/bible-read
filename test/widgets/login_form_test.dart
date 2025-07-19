import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/login_form.dart';

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
}

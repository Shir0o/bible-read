import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/signup_form.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
  });
}

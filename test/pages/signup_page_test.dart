import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

import 'package:bible_read/pages/signup_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    return super.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('SignupPage creates account, writes user doc and navigates', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final auth = RecordingAuth();
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: SignupPage(auth: auth, firestore: firestore),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('signupEmailField')),
      'user@example.com',
    );
    await tester.enterText(find.byKey(const Key('signupPasswordField')), 'pw');
    await tester.enterText(find.byKey(const Key('signupConfirmField')), 'pw');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign Up'));
    await tester.pumpAndSettle();

    expect(auth.createCalled, isTrue);
    expect(auth.email, 'user@example.com');
    expect(auth.password, 'pw');
    final uid = auth.currentUser!.uid;
    final doc = await firestore.collection('users').doc(uid).get();
    expect(doc.exists, isTrue);
    expect(find.byType(MainPage), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  });
}

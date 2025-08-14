import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

import 'package:bible_read/pages/login_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('LoginPage signs in and navigates to MainPage', (tester) async {
    final auth = RecordingAuth();
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(MaterialApp(home: LoginPage(auth: auth)));

    await tester.enterText(
        find.byKey(const Key('loginEmailField')), 'user@example.com');
    await tester.enterText(find.byKey(const Key('loginPasswordField')), 'pw');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(auth.signInCalled, isTrue);
    expect(auth.email, 'user@example.com');
    expect(auth.password, 'pw');
    expect(find.byType(MainPage), findsOneWidget);
  });
}

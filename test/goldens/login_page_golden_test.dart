import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/pages/login_page.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:google_sign_in_mocks/google_sign_in_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import '../helpers/pump_golden.dart';

void main() {
  testWidgets('LoginPage Golden Test', (tester) async {
    final auth = MockFirebaseAuth();

    await tester.pumpGolden(
      LoginPage(
        auth: auth,
        firestore: FakeFirebaseFirestore(),
        googleSignInProvider: () => MockGoogleSignIn(),
      ),
      brightness: Brightness.light,
    );

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(LoginPage),
      matchesGoldenFile('goldens/login_page.png'),
    );
  });
}

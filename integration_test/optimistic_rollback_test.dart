import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import '../test/helpers/fake_google_sign_in_platform.dart';

import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/services/google_sign_in_factory.dart';

// ignore: subtype_of_sealed_class
class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class SelectiveThrowingFirestore extends FakeFirebaseFirestore {
  bool shouldThrowOnSet = false;

  @override
  DocumentReference<Map<String, dynamic>> doc(String path) {
    if (shouldThrowOnSet && path.contains('reading/')) {
      final mock = MockDocumentReference();
      when(() => mock.path).thenReturn(path);
      when(() => mock.set(any(), any())).thenThrow(FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'forced failure',
      ));
      return mock;
    }
    return super.doc(path);
  }
}

class FakeSetOptions extends Fake implements SetOptions {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    registerFallbackValue(FakeSetOptions());
  });

  testWidgets('Optimistic UI Rollback on Firestore failure', (tester) async {
    final google = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = google;

    final firestore = SelectiveThrowingFirestore();
    final mockUser = MockUser(
      uid: 'u1',
      displayName: 'Test User',
      email: 'test@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

    await firestore.collection('users').doc('u1').set({
      'displayName': 'Test User',
      'email': 'test@example.com',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          firestore: firestore,
          auth: auth,
          googleSignInProvider: createGoogleSignIn,
          markFirstReader: ({required dateKey, required uid}) async {
            if (firestore.shouldThrowOnSet) {
              await Future.delayed(const Duration(milliseconds: 200));
              throw FirebaseException(
                plugin: 'cloud_firestore',
                code: 'permission-denied',
                message: 'forced failure',
              );
            }
            return null;
          },
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(milliseconds: 2000));

    final toggleFinder = find.text('I have read');
    final fallbackToggleFinder = find.text('Yes, I read');
    final actualToggle =
        tester.any(toggleFinder) ? toggleFinder : fallbackToggleFinder;

    expect(tester.any(actualToggle), isTrue);

    firestore.shouldThrowOnSet = true;
    await tester.tap(actualToggle);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Thank you'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final foundReadState =
        find.byKey(const ValueKey('read_state')).evaluate().isNotEmpty;
    final foundUnreadState =
        find.byKey(const ValueKey('unread_state')).evaluate().isNotEmpty;
    debugPrint(
        'AFTER ROLLBACK: foundReadState=$foundReadState, foundUnreadState=$foundUnreadState');
    debugPrint('ACTUAL TOGGLE FINDER MATCHES: ${tester.any(actualToggle)}');

    expect(tester.any(actualToggle), isTrue);
    expect(
        find.text('Failed to mark reading. Please try again.'), findsOneWidget);
  });
}

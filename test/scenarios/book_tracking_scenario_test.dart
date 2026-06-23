import 'package:bible_read/pages/bible_progress_page.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import '../helpers/mock_lottie_http_client.dart';
import '../helpers/fake_google_sign_in_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
    setupLottieHttpOverrides();
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();
  });

  testWidgets(
    'Scenario: Complete book via group reading and verify library update',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final user = MockUser(uid: 'u1', displayName: 'Test User');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

      // 1. Seed a group where Ruth (4 chapters) is scheduled
      final groupRef = firestore.collection('groups').doc('g1');
      await groupRef.set({'ownerUid': user.uid, 'name': 'Ruth Study'});
      await groupRef.collection('members').doc(user.uid).set({'uid': user.uid});

      // Ruth 1-4 scheduled on one day
      final chapters = ['Ruth 1', 'Ruth 2', 'Ruth 3', 'Ruth 4'];
      await groupRef.collection('schedule').doc('2024-05-01').set({
        'chapters': chapters,
        'date': Timestamp.fromDate(DateTime(2024, 5, 1)),
      });

      // 2. Mark as read in Firestore
      await groupRef
          .collection('progress')
          .doc('2024-05-01')
          .collection('entries')
          .doc(user.uid)
          .set({
        'uid': user.uid,
        'done': true,
        'count': 4,
        'dateId': '2024-05-01',
      });

      // 3. Open the Bible Library (Path redesign moved it off the Journey tab;
      // it now lives on its own page, reachable from the app menu).
      await tester.pumpWidget(
        MaterialApp(
          home: BibleProgressPage(
            auth: auth,
            firestore: firestore,
            vibrationService: const VibrationService(),
          ),
        ),
      );

      // Allow for initial data loading.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // 4. Verify Ruth is marked completed in the library (History category).
      expect(find.text('HISTORY'), findsOneWidget);
      expect(find.bySemanticsLabel('Ruth, Completed'), findsOneWidget);
    },
  );
}

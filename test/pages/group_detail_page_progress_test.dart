import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group.dart';
import 'package:bible_read/pages/group_detail_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/error_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late Group group;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    group = const Group(id: 'g1', name: 'Test Group', ownerUid: 'u1');
    ErrorLogger.muteForTest = true;
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required GroupService service,
    required MockFirebaseAuth auth,
    DateTime? currentDate,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GroupDetailPage(
          group: group,
          groupService: service,
          auth: auth,
          currentDate: currentDate,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Correctly shows Actual Group Progress (25%) instead of Time Progress',
    (tester) async {
      // 1. Setup Group
      await firestore.collection('groups').doc('g1').set(group.toFirestore());

      // 2. Setup Members (u1, u2)
      final membersRef =
          firestore.collection('groups').doc('g1').collection('members');
      await membersRef.doc('u1').set({
        'uid': 'u1',
        'name': 'User 1',
        'role': 'owner',
      });
      await membersRef.doc('u2').set({
        'uid': 'u2',
        'name': 'User 2',
        'role': 'member',
      });

      // 3. Setup Schedule (100 days, 1 chapter/day)
      final scheduleRef =
          firestore.collection('groups').doc('g1').collection('schedule');
      for (int i = 0; i < 100; i++) {
        final date = DateTime(2024, 1, 1).add(Duration(days: i));
        final dateId =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        await scheduleRef.doc(dateId).set({
          'date': Timestamp.fromDate(date),
          'chapters': ['Ch $i'],
        });
      }

      // 4. Setup Progress Summary
      // u1 has read 50 chapters (50%).
      // u2 has read 0 chapters (0%).
      // Average = 25%.
      final summaryRef = firestore
          .collection('groups')
          .doc('g1')
          .collection('progressSummary')
          .doc('data')
          .collection('entries');

      await summaryRef.doc('u1').set({'completed': 50});
      await summaryRef.doc('u2').set({'completed': 0});

      // 5. Set Current Date to Day 80 (80% Time Progress)
      final currentDate = DateTime(2024, 1, 1).add(const Duration(days: 80));

      auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
      final service = GroupService(firestore: firestore);

      await pumpPage(
        tester,
        service: service,
        auth: auth,
        currentDate: currentDate,
      );

      // Expected Behavior: Shows 25% (Actual Progress)
      expect(find.text('25%'), findsOneWidget);

      // Status should be "Behind" (25% < 81%)
      expect(find.text('Behind'), findsOneWidget);

      // Text description update
      expect(find.textContaining('25% through the Book of Ch'), findsOneWidget);
    },
  );
}

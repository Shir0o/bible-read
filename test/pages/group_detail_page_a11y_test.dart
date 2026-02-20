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
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/services/error_logger.dart';

// Mock setup helpers
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
    group = const Group(id: 'g1', name: 'Study', ownerUid: 'u1');
    ErrorLogger.muteForTest = true;
  });

  Future<void> pumpUntilSettled(
    WidgetTester tester, {
    Duration step = const Duration(milliseconds: 50),
    int maxSteps = 200,
  }) async {
    final binding = tester.binding;
    for (var i = 0; i < maxSteps; i++) {
      await tester.pump(step);
      if (!binding.hasScheduledFrame && binding.transientCallbackCount == 0) {
        return;
      }
    }
    await tester.pump();
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    required GroupService service,
    required MockFirebaseAuth auth,
    VibrationService? vibrationService,
    DateTime? currentDate,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GroupDetailPage(
          group: group,
          groupService: service,
          auth: auth,
          vibrationService: vibrationService,
          currentDate: currentDate,
        ),
      ),
    );
    await pumpUntilSettled(tester);
  }

  testWidgets('members list items have accessible semantic labels',
      (tester) async {
    // Setup group and members
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    final members =
        firestore.collection('groups').doc('g1').collection('members');

    // User 1: Read today
    await members.doc('u1').set({
      'uid': 'u1',
      'role': 'owner',
      'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
    });
    await firestore.collection('users').doc('u1').set({'name': 'Owner'});

    // User 2: Not read yet
    await members.doc('u2').set({
      'uid': 'u2',
      'role': 'member',
      'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 2)),
    });
    await firestore.collection('users').doc('u2').set({'name': 'Alice'});

    // User 1 progress (done)
    final dateKey = '2020-01-01';
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('progress')
        .doc(dateKey)
        .collection('entries')
        .doc('u1')
        .set({
      'uid': 'u1',
      'done': true,
      'count': 1,
    });

    // Add item to subcollection so completion is calculated correctly
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('progress')
        .doc(dateKey)
        .collection('entries')
        .doc('u1')
        .collection('items')
        .doc('0')
        .set({'done': true});

    // Schedule
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('schedule')
        .doc(dateKey)
        .set({
      'date': Timestamp.fromDate(DateTime(2020, 1, 1)),
      'chapters': ['Gen 1'],
    });

    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);

    await pumpPage(
      tester,
      service: GroupService(firestore: firestore),
      auth: auth,
      currentDate: DateTime(2020, 1, 1),
    );

    // Verify Semantics
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Owner, Read today'), findsOneWidget);
    expect(find.bySemanticsLabel('Alice, Not yet'), findsOneWidget);
    handle.dispose();
  });
}

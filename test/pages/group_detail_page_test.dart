import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group.dart';
import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/pages/group_detail_page.dart';
import 'package:bible_read/services/group_service.dart';

class RecordingGroupService extends GroupService {
  RecordingGroupService({required super.firestore});

  bool failUpdate = false;
  GroupSchedule? lastSchedule;

  @override
  Future<void> updateSchedule({
    required String groupId,
    required GroupSchedule schedule,
  }) async {
    if (failUpdate) {
      throw FirebaseException(plugin: 'firestore');
    }
    lastSchedule = schedule;
    await super.updateSchedule(groupId: groupId, schedule: schedule);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late Group group;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    group = const Group(id: 'g1', name: 'Study', ownerUid: 'u1');
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required GroupService service,
    required MockFirebaseAuth auth,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GroupDetailPage(
          group: group,
          groupService: service,
          auth: auth,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('displays members and schedule', (tester) async {
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    final members =
        firestore.collection('groups').doc('g1').collection('members');
    await members.doc('u1').set({
      'uid': 'u1',
      'role': 'owner',
      'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
    });
    await members.doc('u2').set({
      'uid': 'u2',
      'role': 'member',
      'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 2)),
    });
    await firestore.collection('users').doc('u1').set({'name': 'Owner'});
    await firestore.collection('users').doc('u2').set({'name': 'Alice'});
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('schedule')
        .doc('2020-01-01')
        .set({
      'date': Timestamp.fromDate(DateTime(2020, 1, 1)),
      'chapters': ['Gen 1'],
    });
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);

    await pumpPage(tester,
        service: GroupService(firestore: firestore), auth: auth);

    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Gen 1'), findsOneWidget);
  });

  testWidgets('edit schedule success', (tester) async {
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    final service = RecordingGroupService(firestore: firestore);

    await pumpPage(tester, service: service, auth: auth);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ex 1');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(service.lastSchedule?.chapters, ['Ex 1']);
    expect(find.text('Ex 1'), findsOneWidget);
  });

  testWidgets('edit schedule failure shows error and reverts', (tester) async {
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('schedule')
        .doc('2020-01-01')
        .set({
      'date': Timestamp.fromDate(DateTime(2020, 1, 1)),
      'chapters': ['Gen 1'],
    });
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    final service = RecordingGroupService(firestore: firestore)
      ..failUpdate = true;

    await pumpPage(tester, service: service, auth: auth);

    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Gen 2');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Failed to update schedule'), findsOneWidget);
    expect(find.text('Gen 1'), findsOneWidget);
    expect(find.text('Gen 2'), findsNothing);
  });

  testWidgets('fab visible only to owner', (tester) async {
    await firestore.collection('groups').doc('g1').set(group.toFirestore());

    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await pumpPage(tester,
        service: GroupService(firestore: firestore), auth: auth);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u2'), signedIn: true);
    await pumpPage(tester,
        service: GroupService(firestore: firestore), auth: auth);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('changing schedule date deletes old document', (tester) async {
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('schedule')
        .doc('2020-01-01')
        .set({
      'date': Timestamp.fromDate(DateTime(2020, 1, 1)),
      'chapters': ['Gen 1'],
    });
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);

    await pumpPage(tester,
        service: GroupService(firestore: firestore), auth: auth);

    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    await tester.tap(find.text('2020-01-01'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final oldDoc = await firestore
        .collection('groups')
        .doc('g1')
        .collection('schedule')
        .doc('2020-01-01')
        .get();
    final newDoc = await firestore
        .collection('groups')
        .doc('g1')
        .collection('schedule')
        .doc('2020-01-02')
        .get();
    expect(oldDoc.exists, isFalse);
    expect(newDoc.exists, isTrue);
  });
}

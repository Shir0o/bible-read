import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group.dart';
import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/pages/group_detail_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/vibration_service.dart';

class RecordingGroupService extends GroupService {
  RecordingGroupService({required super.firestore});

  bool failUpdate = false;
  GroupSchedule? lastSchedule;
  bool failJoin = false;
  String? joinedGroupId;
  String? joinedUid;
  String? joinedName;

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

  @override
  Future<void> joinGroup({
    required String groupId,
    required String uid,
    required String name,
  }) async {
    joinedGroupId = groupId;
    joinedUid = uid;
    joinedName = name;
    if (failJoin) {
      throw FirebaseException(plugin: 'firestore');
    }
    await super.joinGroup(groupId: groupId, uid: uid, name: name);
  }
}

class _RecordingVibrationService extends VibrationService {
  int lightCount = 0;

  @override
  Future<void> lightImpact() async {
    lightCount++;
  }
}

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
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required GroupService service,
    required MockFirebaseAuth auth,
    VibrationService? vibrationService,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GroupDetailPage(
          group: group,
          groupService: service,
          auth: auth,
          vibrationService: vibrationService,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpAndNavigate(
    WidgetTester tester, {
    required GroupService service,
    required MockFirebaseAuth auth,
    VibrationService? vibrationService,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => GroupDetailPage(
                  group: group,
                  groupService: service,
                  auth: auth,
                  vibrationService: vibrationService,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
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
    final vibration = _RecordingVibrationService();

    await pumpPage(
      tester,
      service: service,
      auth: auth,
      vibrationService: vibration,
    );

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ex 1');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(vibration.lightCount, 2);
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

    await pumpPage(
      tester,
      service: service,
      auth: auth,
      vibrationService: _RecordingVibrationService(),
    );

    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Gen 2');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Failed to update schedule'), findsOneWidget);
    expect(find.text('Gen 1'), findsOneWidget);
    expect(find.text('Gen 2'), findsNothing);
  });

  testWidgets('fab visible to owners and admins', (tester) async {
    await firestore.collection('groups').doc('g1').set(group.toFirestore());

    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await pumpPage(tester,
        service: GroupService(firestore: firestore), auth: auth);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u2')
        .set({
      'uid': 'u2',
      'role': 'admin',
      'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 2)),
    });
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u2'), signedIn: true);
    await pumpPage(tester,
        service: GroupService(firestore: firestore), auth: auth);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u3')
        .set({
      'uid': 'u3',
      'role': 'member',
      'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 3)),
    });
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u3'), signedIn: true);
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

  testWidgets('join button via navigation sends join request', (tester) async {
    group = const Group(id: 'g1', name: 'Study', ownerUid: 'u1');
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u2', displayName: 'User'), signedIn: true);
    final service = RecordingGroupService(firestore: firestore);

    final vibration = _RecordingVibrationService();

    await pumpAndNavigate(
      tester,
      service: service,
      auth: auth,
      vibrationService: vibration,
    );

    await tester.tap(find.text('Join Group'));
    await tester.pumpAndSettle();

    expect(service.joinedGroupId, 'g1');
    expect(service.joinedUid, 'u2');
    expect(service.joinedName, 'User');
    expect(find.text('Join request sent'), findsOneWidget);
    expect(find.text('Join Group'), findsNothing);
    expect(vibration.lightCount, 1);
  });

  testWidgets('join button via navigation failure shows error', (tester) async {
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u2', displayName: 'User'), signedIn: true);
    final service = RecordingGroupService(firestore: firestore)
      ..failJoin = true;

    await pumpAndNavigate(
      tester,
      service: service,
      auth: auth,
      vibrationService: _RecordingVibrationService(),
    );

    await tester.tap(find.text('Join Group'));
    await tester.pumpAndSettle();

    expect(service.joinedGroupId, 'g1');
    expect(find.text('Failed to join group'), findsOneWidget);
    expect(find.text('Join Group'), findsOneWidget);
  });

  testWidgets('pending join request hides join button', (tester) async {
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('joinRequests')
        .doc('u2')
        .set({
      'uid': 'u2',
      'name': 'User',
    });
    auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u2', displayName: 'User'), signedIn: true);
    final service = GroupService(firestore: firestore);

    await pumpPage(tester, service: service, auth: auth);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await pumpPage(tester, service: service, auth: auth);

    expect(find.text('Join Group'), findsNothing);
    expect(find.text('Join request pending'), findsOneWidget);
  });
}

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

class RecordingDeleteGroupService extends GroupService {
  RecordingDeleteGroupService({required super.firestore});

  String? deletedGroupId;
  String? deletedOwnerUid;
  bool failDelete = false;

  @override
  Future<void> deleteGroup({
    required String groupId,
    required String ownerUid,
  }) async {
    deletedGroupId = groupId;
    deletedOwnerUid = ownerUid;
    if (failDelete) {
      throw Exception('delete failed');
    }
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
    GroupDatePicker? datePicker,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GroupDetailPage(
          group: group,
          groupService: service,
          auth: auth,
          vibrationService: vibrationService,
          datePicker: datePicker,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows FAB only in edit mode for admins', (tester) async {
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u1')
        .set({
      'uid': 'u1',
      'role': 'owner',
      'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
    });
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);

    await pumpPage(
      tester,
      service: GroupService(firestore: firestore),
      auth: auth,
    );

    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  Future<void> pumpAndNavigate(
    WidgetTester tester, {
    required GroupService service,
    required MockFirebaseAuth auth,
    VibrationService? vibrationService,
    GroupDatePicker? datePicker,
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
                  datePicker: datePicker,
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

    await pumpPage(
      tester,
      service: GroupService(firestore: firestore),
      auth: auth,
      datePicker: ({
        required BuildContext context,
        required DateTime initialDate,
        required DateTime firstDate,
        required DateTime lastDate,
      }) async =>
          DateTime(2020, 1, 2),
    );

    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(
      find.text('2020-01-01', skipOffstage: false),
      findsWidgets,
    );
  });

  testWidgets('edit schedule success', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    final service = RecordingGroupService(firestore: firestore);
    final vibration = _RecordingVibrationService();

    await pumpPage(
      tester,
      service: service,
      auth: auth,
      vibrationService: vibration,
      datePicker: ({
        required BuildContext context,
        required DateTime initialDate,
        required DateTime firstDate,
        required DateTime lastDate,
      }) async =>
          null,
    );

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final dialogField = find.byType(TextField).last;
    await tester.enterText(dialogField, 'Ex 1');
    await tester.tap(find.byKey(const ValueKey('schedule-save-button')));
    await tester.pumpAndSettle();

    expect(vibration.lightCount, 2);
    expect(service.lastSchedule?.chapters, ['Exodus 1']);
    expect(find.text('Exodus 1'), findsOneWidget);
  });

  testWidgets('edit schedule failure shows error and reverts', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
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
      datePicker: ({
        required BuildContext context,
        required DateTime initialDate,
        required DateTime firstDate,
        required DateTime lastDate,
      }) async =>
          null,
    );

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.edit));
    await tester.pumpAndSettle();
    final editField = find.byType(TextField).last;
    await tester.enterText(editField, 'Gen 2');
    await tester.tap(find.byKey(const ValueKey('schedule-save-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.runAsync(() async {
      final doc = await firestore
          .collection('groups')
          .doc('g1')
          .collection('schedule')
          .doc('2020-01-01')
          .get();
      expect(doc.exists, isTrue);
      expect(doc.data()?['chapters'], ['Gen 1']);
    });
  });

  testWidgets('fab visible to admins only while editing', (tester) async {
    await firestore.collection('groups').doc('g1').set(group.toFirestore());

    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await pumpPage(
      tester,
      service: GroupService(firestore: firestore),
      auth: auth,
      datePicker: ({
        required BuildContext context,
        required DateTime initialDate,
        required DateTime firstDate,
        required DateTime lastDate,
      }) async =>
          DateTime(2020, 1, 2),
    );
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

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
    await pumpPage(
      tester,
      service: GroupService(firestore: firestore),
      auth: auth,
      datePicker: ({
        required BuildContext context,
        required DateTime initialDate,
        required DateTime firstDate,
        required DateTime lastDate,
      }) async =>
          DateTime(2020, 1, 2),
    );
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

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
    await pumpPage(
      tester,
      service: GroupService(firestore: firestore),
      auth: auth,
    );
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byTooltip('Edit'), findsNothing);
  });

  test('changing schedule date deletes old document', () async {
    final firestore = FakeFirebaseFirestore();
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

    final service = GroupService(firestore: firestore);
    await service.deleteSchedule(groupId: 'g1', date: DateTime(2020, 1, 1));
    await service.updateSchedule(
      groupId: 'g1',
      schedule: GroupSchedule(
        date: DateTime(2020, 1, 2),
        chapters: const ['Gen 1'],
      ),
    );

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
      mockUser: MockUser(uid: 'u2', displayName: 'User'),
      signedIn: true,
    );
    final service = RecordingGroupService(firestore: firestore);

    final vibration = _RecordingVibrationService();

    await pumpAndNavigate(
      tester,
      service: service,
      auth: auth,
      vibrationService: vibration,
    );

    await tester.tap(find.text('Join Group'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

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
      mockUser: MockUser(uid: 'u2', displayName: 'User'),
      signedIn: true,
    );
    final service = RecordingGroupService(firestore: firestore)
      ..failJoin = true;

    await pumpAndNavigate(
      tester,
      service: service,
      auth: auth,
      vibrationService: _RecordingVibrationService(),
    );

    await tester.tap(find.text('Join Group'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

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
        .set({'uid': 'u2', 'name': 'User'});
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u2', displayName: 'User'),
      signedIn: true,
    );
    final service = GroupService(firestore: firestore);

    await pumpPage(tester, service: service, auth: auth);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await pumpPage(tester, service: service, auth: auth);

    expect(find.text('Join Group'), findsNothing);
    expect(find.text('Join request pending'), findsOneWidget);
  });

  testWidgets('owner can delete group from edit mode', (tester) async {
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u1')
        .set({
      'uid': 'u1',
      'role': 'owner',
      'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
    });
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    final service = RecordingDeleteGroupService(firestore: firestore);

    await pumpAndNavigate(
      tester,
      service: service,
      auth: auth,
    );

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    final deleteFinder = find.byKey(const Key('delete-group-button'));
    expect(deleteFinder, findsOneWidget);

    await tester.tap(deleteFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(service.deletedGroupId, 'g1');
    expect(service.deletedOwnerUid, 'u1');
    expect(find.byType(GroupDetailPage), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('delete failure shows snackbar and keeps page open',
      (tester) async {
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u1')
        .set({
      'uid': 'u1',
      'role': 'owner',
      'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
    });
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    final service = RecordingDeleteGroupService(firestore: firestore)
      ..failDelete = true;

    await pumpAndNavigate(
      tester,
      service: service,
      auth: auth,
    );

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete-group-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(service.deletedGroupId, 'g1');
    expect(find.text('Failed to delete group'), findsOneWidget);
    expect(find.byType(GroupDetailPage), findsOneWidget);
  });

  testWidgets('admins who are not owners cannot delete group', (tester) async {
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
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
    final service = RecordingDeleteGroupService(firestore: firestore);

    await pumpAndNavigate(
      tester,
      service: service,
      auth: auth,
    );

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('delete-group-button')), findsNothing);
  });
}

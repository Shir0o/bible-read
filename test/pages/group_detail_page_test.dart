import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group.dart';
import 'package:bible_read/pages/group_detail_page.dart';
import 'package:bible_read/pages/edit_group_page.dart';
import 'package:bible_read/services/achievement_service.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/widgets/schedule_item_tile.dart';
import 'package:bible_read/services/error_logger.dart';

class RecordingGroupService extends GroupService {
  RecordingGroupService({required super.firestore});

  bool failJoin = false;
  String? joinedGroupId;
  String? joinedUid;
  String? joinedName;

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
      throw FirebaseException(
        plugin: 'firestore',
        message: 'Failed to join group',
      );
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
    await pumpUntilSettled(tester);
  }

  testWidgets('tapping Edit navigates to EditGroupPage for admins',
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

    await pumpPage(
      tester,
      service: GroupService(firestore: firestore),
      auth: auth,
    );

    expect(find.byTooltip('Edit Group Plan'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit Group Plan'));
    await pumpUntilSettled(tester);

    expect(find.byType(EditGroupPage), findsOneWidget);
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
    await pumpUntilSettled(tester);
    await tester.tap(find.text('open'));
    await pumpUntilSettled(tester);
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
    expect(find.text('2020-01-01', skipOffstage: false), findsWidgets);
  });

  testWidgets('Edit button hidden for non-admins', (tester) async {
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
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
    expect(find.byTooltip('Edit Group Plan'), findsNothing);
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
    await tester.pump(const Duration(milliseconds: 200));

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
    await pumpUntilSettled(tester);
    await pumpPage(tester, service: service, auth: auth);

    expect(find.text('Join Group'), findsNothing);
    expect(find.text('Join request pending'), findsOneWidget);
  });

  testWidgets('marking final chapter unlocks book achievement', (tester) async {
    final groupRef = firestore.collection('groups').doc('g1');
    await groupRef.set(group.toFirestore());
    await groupRef.collection('members').doc('u1').set({
      'uid': 'u1',
      'role': 'owner',
      'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 6, 1)),
    });

    Future<void> seedSchedule({
      required String dateId,
      required DateTime date,
      required List<String> chapters,
    }) async {
      await groupRef.collection('schedule').doc(dateId).set({
        'date': Timestamp.fromDate(date),
        'chapters': chapters,
      });
    }

    Future<void> seedProgress({
      required String dateId,
      required List<int> completedIndices,
    }) async {
      final entryRef = groupRef
          .collection('progress')
          .doc(dateId)
          .collection('entries')
          .doc('u1');
      await entryRef.set({
        'uid': 'u1',
        'groupId': 'g1',
        'dateId': dateId,
        'count': completedIndices.length,
      });
      for (final index in completedIndices) {
        await entryRef.collection('items').doc(index.toString()).set({
          'done': true,
          'ts': Timestamp.fromDate(DateTime.utc(2024, 6, 1)),
        });
      }
    }

    await seedSchedule(
      dateId: '2024-06-01',
      date: DateTime.utc(2024, 6, 1),
      chapters: const ['Ruth 1', 'Ruth 2'],
    );
    await seedSchedule(
      dateId: '2024-06-02',
      date: DateTime.utc(2024, 6, 2),
      chapters: const ['Ruth 3', 'Ruth 4'],
    );

    await seedProgress(dateId: '2024-06-01', completedIndices: const [0, 1]);
    await seedProgress(dateId: '2024-06-02', completedIndices: const [0]);

    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    final service = GroupService(firestore: firestore);

    final achievementsCollection = firestore
        .collection('users')
        .doc('u1')
        .collection(AchievementService.achievementsCollection);
    expect(
      (await achievementsCollection.doc('book_ruth').get()).exists,
      isFalse,
    );

    await pumpPage(tester, service: service, auth: auth);

    final chipFinder = find.widgetWithText(FilterChip, 'Ruth 4');
    expect(chipFinder, findsOneWidget);

    final scrollable = find.byType(Scrollable).last;
    await tester.fling(scrollable, const Offset(0, -600), 1000);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      chipFinder,
      200,
      scrollable: scrollable,
    );
    await tester.tap(chipFinder);
    await tester.pump();
    await pumpUntilSettled(tester);

    final achievementSnap = await achievementsCollection.doc('book_ruth').get();
    expect(achievementSnap.exists, isTrue);
    final data = achievementSnap.data() ?? <String, dynamic>{};
    expect(data['type'], 'book');
    expect(data['title'], 'Complete Ruth');
    expect(data['dateUnlocked'], isA<Timestamp>());
  });

  testWidgets('marking schedule read unlocks book achievement', (tester) async {
    final groupRef = firestore.collection('groups').doc('g1');
    await groupRef.set(group.toFirestore());
    await groupRef.collection('members').doc('u1').set({
      'uid': 'u1',
      'role': 'owner',
      'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 6, 1)),
    });

    Future<void> seedSchedule({
      required String dateId,
      required DateTime date,
      required List<String> chapters,
    }) async {
      await groupRef.collection('schedule').doc(dateId).set({
        'date': Timestamp.fromDate(date),
        'chapters': chapters,
      });
    }

    Future<void> seedProgress({
      required String dateId,
      required List<int> completedIndices,
    }) async {
      final entryRef = groupRef
          .collection('progress')
          .doc(dateId)
          .collection('entries')
          .doc('u1');
      await entryRef.set({
        'uid': 'u1',
        'groupId': 'g1',
        'dateId': dateId,
        'count': completedIndices.length,
      });
      for (final index in completedIndices) {
        await entryRef.collection('items').doc(index.toString()).set({
          'done': true,
          'ts': Timestamp.fromDate(DateTime.utc(2024, 6, 1)),
        });
      }
    }

    await seedSchedule(
      dateId: '2024-06-01',
      date: DateTime.utc(2024, 6, 1),
      chapters: const ['Ruth 1', 'Ruth 2'],
    );
    await seedSchedule(
      dateId: '2024-06-02',
      date: DateTime.utc(2024, 6, 2),
      chapters: const ['Ruth 3', 'Ruth 4'],
    );

    await seedProgress(dateId: '2024-06-01', completedIndices: const [0, 1]);
    // Pre-seed empty progress for the target day to ensure the document exists.
    // This avoids FakeFirebaseFirestore issues with collectionGroup queries on newly created docs.
    await seedProgress(dateId: '2024-06-02', completedIndices: const []);

    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    final service = GroupService(firestore: firestore);

    final achievementsCollection = firestore
        .collection('users')
        .doc('u1')
        .collection(AchievementService.achievementsCollection);
    expect(
      (await achievementsCollection.doc('book_ruth').get()).exists,
      isFalse,
    );

    await pumpPage(tester, service: service, auth: auth);

    final scheduleTileFinder = find.ancestor(
      of: find.text('2024-06-02'),
      matching: find.byType(ScheduleItemTile),
    );
    final checkboxFinder = find.descendant(
      of: scheduleTileFinder,
      matching: find.byType(Checkbox),
    );

    expect(checkboxFinder, findsOneWidget);
    expect(tester.widget<Checkbox>(checkboxFinder).value, isFalse);

    await tester.tap(checkboxFinder);
    await tester.pump();
    await pumpUntilSettled(tester);

    final achievementSnap = await achievementsCollection.doc('book_ruth').get();
    expect(achievementSnap.exists, isTrue);
    final data = achievementSnap.data() ?? <String, dynamic>{};
    expect(data['type'], 'book');
    expect(data['title'], 'Complete Ruth');
    expect(data['dateUnlocked'], isA<Timestamp>());
  });

  testWidgets('non-members see read-only schedule tiles', (tester) async {
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('schedule')
        .doc('2024-07-01')
        .set({
      'date': Timestamp.fromDate(DateTime(2024, 7, 1)),
      'chapters': ['Gen 1', 'Gen 2'],
    });
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u2'), signedIn: true);

    await pumpPage(
      tester,
      service: GroupService(firestore: firestore),
      auth: auth,
    );

    final scheduleTileFinder = find.ancestor(
      of: find.text('2024-07-01'),
      matching: find.byType(ScheduleItemTile),
    );

    expect(scheduleTileFinder, findsOneWidget);
    expect(
      find.descendant(of: scheduleTileFinder, matching: find.byType(Checkbox)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: scheduleTileFinder,
        matching: find.byType(FilterChip),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: scheduleTileFinder,
        matching: find.text('Gen 1, Gen 2'),
      ),
      findsOneWidget,
    );
  });
}

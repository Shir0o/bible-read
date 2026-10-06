import 'package:bible_read/pages/adjust_pace_page.dart';
import 'package:bible_read/pages/create_plan_page.dart';
import 'package:bible_read/models/group.dart';
import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/widgets/journey/plans_hub.dart';
import 'package:bible_read/widgets/skeletons/plans_hub_skeleton.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/plan_pace_service.dart';
import 'package:bible_read/services/reading_plan_service.dart';
import 'package:bible_read/services/user_preferences_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubVibrationService extends VibrationService {
  const _StubVibrationService();
  @override
  Future<void> lightImpact() async {}
  @override
  Future<void> mediumImpact() async {}
}

// Simulates a group query failing in production (e.g. a missing composite
// index): the hub must still render the personal plans it already loaded.
class _ThrowingGroupService extends GroupService {
  _ThrowingGroupService({required super.firestore});
  @override
  Future<List<Group>> archivedGroupsForUser(String uid) async {
    throw Exception('simulated missing index');
  }
}

// A two-day plan starting today, so it is active (not yet complete).
const _plan = ReadingPlan(
  id: 'p1',
  title: 'Morning Light',
  description: 'A gentle daily reading',
  durationDays: 2,
  tags: [],
  schedule: [
    ReadingPlanDay(day: 1, readings: ['Gen 1']),
    ReadingPlanDay(day: 2, readings: ['Gen 2']),
  ],
);

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late ReadingPlanService planService;
  late GroupService groupService;
  late UserPreferencesService prefsService;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    planService = ReadingPlanService(firestore: firestore);
    groupService = GroupService(firestore: firestore);
    prefsService = UserPreferencesService(firestore: firestore);

    await firestore.collection('custom_plans').doc('p1').set({
      ..._plan.toJson(),
      'userId': 'u1',
    });
    await planService.startPlan('u1', 'p1', startDate: DateTime.now());
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: PlansHub(
            firestore: firestore,
            auth: auth,
            groupService: groupService,
            readingPlanService: planService,
            userPreferencesService: prefsService,
            vibrationService: const _StubVibrationService(),
            dateProvider: DateTime.now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));
  }

  testWidgets('renders the personal plan with the design sections', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('On your own'), findsOneWidget);

    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Enroll in a new plan'), findsOneWidget);
  });

  testWidgets(
      'a failing group query does not hide the personal plans '
      'already loaded', (tester) async {
    // Regression: PlansHub._load() used to abort on the first group query
    // error (missing index in production) and discard the personal plans it
    // had already fetched — the hub showed "No active plans yet" right after
    // a plan was created.
    groupService = _ThrowingGroupService(firestore: firestore);
    await pumpPage(tester);

    expect(find.text('On your own'), findsOneWidget);
    expect(find.text('Morning Light'), findsOneWidget);
    expect(find.text('No active plans yet'), findsNothing);
  });

  testWidgets('pinning a plan persists it as the Home primary', (tester) async {
    await pumpPage(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Pin as Home primary'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    final prefs = await prefsService.fetchPreferences('u1');
    expect(prefs.pinnedReadingId, 'plan:p1');
    expect(find.text('Primary on Home'), findsOneWidget);

    // Tapping again unpins it.
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Unpin from Home'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    final cleared = await prefsService.fetchPreferences('u1');
    expect(cleared.pinnedReadingId, isNull);
  });

  testWidgets('enrolling opens the creation flow with no modal fork', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.text('Enroll in a new plan'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    // The creation form is pushed directly — no personal-vs-group chooser
    // before it (#809). The who-is-reading field sits below the fold.
    expect(find.byType(CreatePlanPage), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('WHO IS READING'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // The who-is-reading answer is a field in the flow, not a fork.
    expect(find.text('Just you'), findsOneWidget);
    expect(find.text('With a group'), findsOneWidget);
  });

  testWidgets(
      'adjust pace is reachable from the plan card and previews '
      'the finish before committing', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adjust pace'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    // The screen is the shared adjust-pace page with the three options, each
    // showing the resulting finish date before the reader commits.
    expect(find.byType(AdjustPacePage), findsOneWidget);
    expect(find.text('Stretch it out'), findsOneWidget);
    expect(find.text('Keep the finish'), findsOneWidget);
    expect(find.text('Begin again'), findsOneWidget);
    expect(find.textContaining('ends'), findsWidgets);

    // Backing out commits nothing.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    final progress = await firestore
        .collection('users')
        .doc('u1')
        .collection('plan_progress')
        .doc('p1')
        .get();
    expect(progress.data()?['completedDays'], isEmpty);
  });
  Future<void> archiveViaMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive plan'));
  }

  testWidgets(
      'archiving a plan moves it to Archived and the archive keeps restore '
      'and permanent delete reachable', (tester) async {
    await pumpPage(tester);

    // Archive is reversible, so it happens straight from the card's menu.
    await archiveViaMenu(tester);
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    var progress = await firestore
        .collection('users')
        .doc('u1')
        .collection('plan_progress')
        .doc('p1')
        .get();
    expect(progress.data()?['isArchived'], isTrue);

    // The card moves to the hub's Archived section — the capabilities the
    // retired duplicate page owned (#811).
    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('Morning Light'), findsOneWidget);

    // Restore returns it to "On your own".
    await tester.tap(find.byTooltip('Unarchive and continue'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));
    progress = await firestore
        .collection('users')
        .doc('u1')
        .collection('plan_progress')
        .doc('p1')
        .get();
    expect(progress.data()?['isArchived'], isFalse);
    expect(find.text('On your own'), findsOneWidget);
    expect(find.byTooltip('Unarchive and continue'), findsNothing);
  });

  testWidgets(
      'delete from the archive moves the plan to Recently Deleted '
      'with a 30-day recovery window', (tester) async {
    await planService.setPlanArchived('u1', 'p1', true);
    await pumpPage(tester);

    expect(find.text('Archived'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete plan'));
    await tester.pumpAndSettle();

    // The dialog names the consequence — 30 days in the trash — and asks.
    expect(find.text('Delete "Morning Light"?'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    final progress = await firestore
        .collection('users')
        .doc('u1')
        .collection('plan_progress')
        .doc('p1')
        .get();
    // The progress document survives in the trash, not destroyed.
    expect(progress.exists, isTrue);
    expect(progress.data()?['deletedAt'], isNotNull);
    expect(progress.data()?['preDeleteState'], 'archived');
    expect(find.text('Archived'), findsNothing);
    expect(find.text('Recently Deleted · 1 waiting'), findsOneWidget);
  });

  testWidgets('Undo on the archive snackbar restores the plan', (
    tester,
  ) async {
    await pumpPage(tester);

    await archiveViaMenu(tester);
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));
    expect(find.text('Archived "Morning Light"'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    final progress = await firestore
        .collection('users')
        .doc('u1')
        .collection('plan_progress')
        .doc('p1')
        .get();
    expect(progress.data()?['isArchived'], isFalse);
    expect(find.text('On your own'), findsOneWidget);
  });

  testWidgets('a long archive collapses to two rows until expanded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final id in ['p2', 'p3']) {
      await firestore.collection('custom_plans').doc(id).set({
        ..._plan.toJson(),
        'id': id,
        'title': 'Plan $id',
        'userId': 'u1',
      });
      await planService.startPlan('u1', id, startDate: DateTime.now());
    }
    for (final id in ['p1', 'p2', 'p3']) {
      await planService.setPlanArchived('u1', id, true);
    }
    await pumpPage(tester);

    expect(find.byTooltip('Unarchive and continue'), findsNWidgets(2));
    await tester.tap(find.text('Show all 3'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unarchive and continue'), findsNWidgets(3));
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('a new plan appears without a manual reload', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpPage(tester);

    const secondPlan = ReadingPlan(
      id: 'p2',
      title: 'Evening Light',
      description: 'A second plan',
      durationDays: 2,
      tags: [],
      schedule: [
        ReadingPlanDay(day: 1, readings: ['John 1']),
        ReadingPlanDay(day: 2, readings: ['John 2']),
      ],
    );

    await tester.runAsync(() async {
      await firestore.collection('custom_plans').doc('p2').set({
        ...secondPlan.toJson(),
        'userId': 'u1',
      });
      await planService.startPlan('u1', 'p2', startDate: DateTime.now());
    });
    await tester.pumpAndSettle(const Duration(milliseconds: 1500));

    expect(find.text('Evening Light'), findsOneWidget);
  });

  testWidgets('archiving a plan displays error SnackBar if backend call fails',
      (
    tester,
  ) async {
    // Throwing reading plan service to simulate failure
    final failingPlanService = _FailingReadingPlanService(firestore: firestore);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: PlansHub(
            firestore: firestore,
            auth: auth,
            groupService: groupService,
            readingPlanService: failingPlanService,
            userPreferencesService: prefsService,
            vibrationService: const _StubVibrationService(),
            dateProvider: DateTime.now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    await archiveViaMenu(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('Failed to archive "Morning Light". Please try again.'),
      findsOneWidget,
    );
  });

  // ---- Finish (ADR-0010) ---------------------------------------------------

  DocumentReference<Map<String, dynamic>> progressRef() => firestore
      .collection('users')
      .doc('u1')
      .collection('plan_progress')
      .doc('p1');

  DocumentReference<Map<String, dynamic>> memberRef(String groupId) => firestore
      .collection('groups')
      .doc(groupId)
      .collection('members')
      .doc('u1');

  /// Moves the seeded two-day plan into the past with day 1 read, so its
  /// dates have ended with one reading still unread (wrap-up).
  Future<void> endPlanWithOneRead() => progressRef().update({
        'startDate': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 10)),
        ),
        'completedDays': [1],
      });

  /// A Shared plan u1 reads as a member: two past readings, the first read,
  /// so its dates have ended with one reading unread. Returns the group id.
  Future<String> seedEndedSharedPlan() async {
    final groupId = await groupService.createGroup(
      ownerUid: 'naomi',
      name: 'Jeremiah Plan',
    );
    await memberRef(groupId).set({'uid': 'u1', 'role': 'member'});
    final today = DateTime.now();
    final first = DateTime(today.year, today.month, today.day - 10);
    final second = DateTime(today.year, today.month, today.day - 9);
    await groupService.updateSchedule(
      groupId: groupId,
      schedule: GroupSchedule(date: first, chapters: const ['Jer 1']),
    );
    await groupService.updateSchedule(
      groupId: groupId,
      schedule: GroupSchedule(date: second, chapters: const ['Jer 2']),
    );
    await firestore
        .collection('groups')
        .doc(groupId)
        .collection('progress')
        .doc(GroupService.dateId(first))
        .collection('entries')
        .doc('u1')
        .set({
      'groupId': groupId,
      'uid': 'u1',
      'dateId': GroupService.dateId(first),
      'count': 1,
      'done': true,
    });
    // Leave only the Shared plan on screen.
    await planService.leavePlan('u1', 'p1');
    return groupId;
  }

  /// A Shared plan u1 is on track with: Jer 1 read yesterday, Jer 2 tomorrow.
  /// With [ownPace] those are the reader's own overlay dates and the Group's
  /// schedule ended 9 days ago; without it they are the Group's dates.
  Future<void> seedOnTrackSharedPlan({required bool ownPace}) async {
    final groupId = await groupService.createGroup(
      ownerUid: 'naomi',
      name: 'Jeremiah Plan',
    );
    await memberRef(groupId).set({'uid': 'u1', 'role': 'member'});
    final today = DateTime.now();
    DateTime day(int offset) =>
        DateTime(today.year, today.month, today.day + offset);
    final own = [
      GroupSchedule(date: day(-1), chapters: const ['Jer 1']),
      GroupSchedule(date: day(1), chapters: const ['Jer 2']),
    ];
    final groupSchedule = ownPace
        ? [
            GroupSchedule(date: day(-10), chapters: const ['Jer 1']),
            GroupSchedule(date: day(-9), chapters: const ['Jer 2']),
          ]
        : own;
    for (final s in groupSchedule) {
      await groupService.updateSchedule(groupId: groupId, schedule: s);
    }
    if (ownPace) {
      await PlanPaceService(firestore: firestore).applySharedPlanOverlay(
        uid: 'u1',
        groupId: groupId,
        adjusted: own,
      );
    }
    final readId = GroupService.dateId(day(-1));
    await firestore
        .collection('groups')
        .doc(groupId)
        .collection('progress')
        .doc(readId)
        .collection('entries')
        .doc('u1')
        .set({
      'groupId': groupId,
      'uid': 'u1',
      'dateId': readId,
      'count': 1,
      'done': true,
    });
    // Leave only the Shared plan on screen.
    await planService.leavePlan('u1', 'p1');
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
  }

  testWidgets('a plan that is still running offers no Finish item', (
    tester,
  ) async {
    await pumpPage(tester);

    await openMenu(tester);
    expect(find.text('Adjust pace'), findsOneWidget);
    expect(find.text('Finish plan'), findsNothing);
  });

  testWidgets(
      'finishing an ended solo plan moves it to Finished with how much was '
      'read, leaves its readings unmarked, and Restore returns it',
      (tester) async {
    await endPlanWithOneRead();
    await pumpPage(tester);

    await openMenu(tester);
    await tester.tap(find.text('Finish plan'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('Finished · 1 of 2 read'), findsOneWidget);
    expect(find.text('On your own'), findsNothing);
    final finished = await progressRef().get();
    expect(finished.data()?['finishedAt'], isNotNull);
    // Finish never marks readings: day 2 stays unread.
    expect(finished.data()?['completedDays'], [1]);

    await tester.tap(find.byTooltip('Restore plan'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    final restored = await progressRef().get();
    expect(restored.data()?['finishedAt'], isNull);
    expect(restored.data()?['completedDays'], [1]);
    expect(find.text('On your own'), findsOneWidget);
    expect(find.text('Finished · 1 of 2 read'), findsNothing);
  });

  testWidgets('Undo on the finish snackbar restores the plan', (tester) async {
    await endPlanWithOneRead();
    await pumpPage(tester);

    await openMenu(tester);
    await tester.tap(find.text('Finish plan'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));
    expect(find.text('Finished "Morning Light"'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    expect((await progressRef().get()).data()?['finishedAt'], isNull);
    expect(find.text('On your own'), findsOneWidget);
    expect(find.text('Finished · 1 of 2 read'), findsNothing);
  });

  testWidgets('a fully-read plan keeps its existing Finished look', (
    tester,
  ) async {
    await progressRef().update({
      'startDate': Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 10)),
      ),
      'completedDays': [1, 2],
    });
    await pumpPage(tester);

    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('All 2 readings complete'), findsOneWidget);
    expect(find.byTooltip('Restore plan'), findsNothing);
  });

  testWidgets(
      'finishing a solo plan displays an error SnackBar and rolls back if the '
      'backend call fails', (tester) async {
    await endPlanWithOneRead();
    planService = _FailingReadingPlanService(firestore: firestore);
    await pumpPage(tester);

    await openMenu(tester);
    await tester.tap(find.text('Finish plan'));
    await tester.pumpAndSettle();

    expect(
      find.text('Failed to finish "Morning Light". Please try again.'),
      findsOneWidget,
    );
    expect(find.text('On your own'), findsOneWidget);
    expect(find.text('Finished · 1 of 2 read'), findsNothing);
  });

  testWidgets(
      'finishing an ended Shared plan closes only the reader\'s own '
      'participation and Restore returns it', (tester) async {
    final groupId = await seedEndedSharedPlan();
    await pumpPage(tester);

    expect(find.text('Together'), findsOneWidget);
    await openMenu(tester);
    await tester.tap(find.text('Finish plan'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    expect(find.text('Finished · 1 of 2 read'), findsOneWidget);
    expect(find.text('Together'), findsNothing);
    final member = await memberRef(groupId).get();
    expect(member.data()?['finishedAt'], isNotNull);
    // Still a full member: nothing about the membership changed.
    expect(member.data()?['role'], 'member');
    expect(member.data()?['isArchived'], isNull);
    expect(
      (await groupService.groupsForUser('u1').first).map((g) => g.id),
      contains(groupId),
    );

    await tester.tap(find.byTooltip('Restore plan'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    expect((await memberRef(groupId).get()).data()?['finishedAt'], isNull);
    expect(find.text('Together'), findsOneWidget);
    expect(find.text('Finished · 1 of 2 read'), findsNothing);
  });

  testWidgets('Undo on the finish snackbar restores a Shared plan', (
    tester,
  ) async {
    final groupId = await seedEndedSharedPlan();
    await pumpPage(tester);

    await openMenu(tester);
    await tester.tap(find.text('Finish plan'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));
    expect(find.text('Finished "Jeremiah Plan"'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    expect((await memberRef(groupId).get()).data()?['finishedAt'], isNull);
    expect(find.text('Together'), findsOneWidget);
  });

  testWidgets(
      "a Shared plan follows the reader's pace overlay, not the Group's "
      'dates', (tester) async {
    final groupId = await seedEndedSharedPlan();
    final today = DateTime.now();
    // The reader's Adjust pace moved the unread reading to today.
    await PlanPaceService(firestore: firestore).applySharedPlanOverlay(
      uid: 'u1',
      groupId: groupId,
      adjusted: [
        GroupSchedule(
          date: DateTime(today.year, today.month, today.day - 10),
          chapters: const ['Jer 1'],
        ),
        GroupSchedule(
          date: DateTime(today.year, today.month, today.day),
          chapters: const ['Jer 2'],
        ),
      ],
    );
    await pumpPage(tester);

    expect(find.text('Together'), findsOneWidget);
    expect(find.text('Due today'), findsOneWidget);
    expect(find.text('Ended'), findsNothing);
  });

  testWidgets(
      'an on-track Shared plan on the Group schedule reads "In step with your '
      'group"', (tester) async {
    await seedOnTrackSharedPlan(ownPace: false);
    await pumpPage(tester);

    expect(find.text('In step with your group'), findsOneWidget);
    expect(find.text("You're on track"), findsNothing);
  });

  testWidgets(
      "an on-track Shared plan on the reader's own pace reads \"You're on "
      'track"', (tester) async {
    await seedOnTrackSharedPlan(ownPace: true);
    await pumpPage(tester);

    expect(find.text("You're on track"), findsOneWidget);
    expect(find.text('In step with your group'), findsNothing);
  });

  testWidgets(
      'a finished Shared plan stays finished when the owner moves the '
      'schedule later, and Restore shows the new dates', (tester) async {
    final groupId = await seedEndedSharedPlan();
    await pumpPage(tester);
    await openMenu(tester);
    await tester.tap(find.text('Finish plan'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    // The owner's Reschedule: the Group schedule now runs into the future.
    final later = DateTime.now().add(const Duration(days: 5));
    await tester.runAsync(
      () => groupService.updateSchedule(
        groupId: groupId,
        schedule: GroupSchedule(
          date: DateTime(later.year, later.month, later.day),
          chapters: const ['Jer 3'],
        ),
      ),
    );
    // Re-open the hub from scratch so it loads the moved schedule.
    await tester.pumpWidget(const SizedBox());
    await pumpPage(tester);

    // Re-opening the hub: the reader's choice stands, now that the plan's
    // dates are no longer over.
    expect((await memberRef(groupId).get()).data()?['finishedAt'], isNotNull);
    expect(find.text('Finished · 1 of 3 read'), findsOneWidget);
    expect(find.text('Together'), findsNothing);

    await tester.tap(find.byTooltip('Restore plan'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    // Back with the new dates: running again, so no longer "Ended".
    expect(find.text('Together'), findsOneWidget);
    expect(find.text('Ended'), findsNothing);
    expect(find.text('Finish plan'), findsNothing);
  });

  testWidgets('renders PlansHubSkeleton while loading', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: PlansHub(
            firestore: firestore,
            auth: auth,
            groupService: groupService,
            readingPlanService: planService,
            userPreferencesService: prefsService,
            vibrationService: const _StubVibrationService(),
            dateProvider: DateTime.now,
          ),
        ),
      ),
    );
    // Pump immediately before load completes / before skeleton minTime passes
    await tester.pump();
    expect(find.byType(PlansHubSkeleton), findsOneWidget);

    // Header and enroll button remain visible during skeleton loading
    expect(find.text('Enroll in a new plan'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(milliseconds: 1200));
    expect(find.byType(PlansHubSkeleton), findsNothing);
  });
}

class _FailingReadingPlanService extends ReadingPlanService {
  _FailingReadingPlanService({required super.firestore});

  @override
  Future<void> setPlanArchived(String uid, String planId, bool archived) async {
    throw Exception('Simulated network failure');
  }

  @override
  Future<void> finishPlan(String userId, String planId) async {
    throw Exception('Simulated network failure');
  }
}

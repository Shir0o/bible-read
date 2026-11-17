import 'package:bible_read/pages/adjust_pace_page.dart';
import 'package:bible_read/pages/create_plan_page.dart';
import 'package:bible_read/models/group.dart';
import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/widgets/journey/plans_hub.dart';
import 'package:bible_read/widgets/skeletons/plans_hub_skeleton.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/reading_plan_service.dart';
import 'package:bible_read/services/user_preferences_service.dart';
import 'package:bible_read/services/vibration_service.dart';
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

class _ThrowingGroupService extends GroupService {
  _ThrowingGroupService({required super.firestore});
  @override
  Stream<List<Group>> groupsForUser(String uid, {bool includeFinished = true}) {
    return Stream.error(Exception('simulated missing index'));
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
    expect(find.text('Enroll in a new plan'), findsNothing);
  });

  testWidgets(
      'a failing group query does not hide the personal plans '
      'already loaded', (tester) async {
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
    firestore = FakeFirebaseFirestore();
    planService = ReadingPlanService(firestore: firestore);
    groupService = GroupService(firestore: firestore);
    prefsService = UserPreferencesService(firestore: firestore);
    await pumpPage(tester);

    await tester.tap(find.text('Enroll in a new plan'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    expect(find.byType(CreatePlanPage), findsOneWidget);
    expect(find.text("Who's reading"), findsOneWidget);
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

    expect(find.byType(AdjustPacePage), findsOneWidget);
    expect(find.text('Stretch it out'), findsOneWidget);
    expect(find.text('Keep the finish'), findsOneWidget);
    expect(find.text('Begin again'), findsOneWidget);
    expect(find.textContaining('ends'), findsWidgets);

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

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
  }

  testWidgets('a plan menu offers Adjust pace, Edit plan, and Delete plan',
      (tester) async {
    await pumpPage(tester);

    await openMenu(tester);
    expect(find.text('Adjust pace'), findsOneWidget);
    expect(find.text('Edit plan'), findsOneWidget);
    expect(find.text('Delete plan'), findsOneWidget);
    expect(find.text('Archive plan'), findsNothing);
    expect(find.text('Finish plan'), findsNothing);
  });

  testWidgets('deleting a personal plan removes it with confirmation',
      (tester) async {
    await pumpPage(tester);

    await openMenu(tester);
    await tester.tap(find.text('Delete plan'));
    await tester.pumpAndSettle();

    expect(find.text('Delete “Morning Light”?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    expect(find.text('On your own'), findsNothing);
    final doc = await firestore
        .collection('users')
        .doc('u1')
        .collection('plan_progress')
        .doc('p1')
        .get();
    expect(doc.exists, isFalse);
  });

  Future<void> seedMemberSharedPlan() async {
    final groupId = await groupService.createGroup(
      ownerUid: 'naomi',
      name: 'Jeremiah Plan',
    );
    await firestore
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc('u1')
        .set({'uid': 'u1', 'role': 'member'});
    final today = DateTime.now();
    await groupService.updateSchedule(
      groupId: groupId,
      schedule: GroupSchedule(
        date: DateTime(today.year, today.month, today.day + 1),
        chapters: const ['Jer 1'],
      ),
    );
    await planService.leavePlan('u1', 'p1');
  }

  Future<String> seedOwnedSharedPlan() async {
    final groupId = await groupService.createGroup(
      ownerUid: 'u1',
      name: 'Jeremiah Plan',
    );
    final today = DateTime.now();
    await groupService.updateSchedule(
      groupId: groupId,
      schedule: GroupSchedule(
        date: DateTime(today.year, today.month, today.day + 1),
        chapters: const ['Jer 1'],
      ),
    );
    await planService.leavePlan('u1', 'p1');
    return groupId;
  }

  testWidgets(
      "a member's Shared plan menu offers Members and invites and Leave plan, not Adjust pace or Delete",
      (tester) async {
    await seedMemberSharedPlan();
    await pumpPage(tester);

    await openMenu(tester);
    expect(find.text('Members and invites'), findsOneWidget);
    expect(find.text('Leave plan'), findsOneWidget);
    expect(find.text('Adjust pace'), findsNothing);
    expect(find.text('Archive'), findsNothing);
    expect(find.text('Delete plan'), findsNothing);
  });

  testWidgets('Leave plan confirms on a dialog, then leaves the plan', (
    tester,
  ) async {
    await seedMemberSharedPlan();
    await pumpPage(tester);

    await openMenu(tester);
    await tester.tap(find.text('Leave plan'));
    await tester.pumpAndSettle();
    expect(find.text('Leave “Jeremiah Plan”?'), findsOneWidget);
    expect(find.text('The plan carries on for everyone else.'), findsOneWidget);

    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    expect(find.text('Together'), findsNothing);
    expect(await groupService.groupsForUser('u1').first, isEmpty);
  });

  testWidgets(
      "an owner's Shared plan menu offers Adjust pace, Members and invites, and Delete plan",
      (tester) async {
    await seedOwnedSharedPlan();
    await pumpPage(tester);

    await openMenu(tester);
    expect(find.text('Adjust pace'), findsOneWidget);
    expect(find.text('Members and invites'), findsOneWidget);
    expect(find.text('Delete plan'), findsOneWidget);
    expect(find.text('Leave plan'), findsNothing);
  });

  testWidgets(
      "an owner's Delete plan deletes the group with a confirmation dialog",
      (tester) async {
    final groupId = await seedOwnedSharedPlan();
    await pumpPage(tester);

    await openMenu(tester);
    await tester.tap(find.text('Delete plan'));
    await tester.pumpAndSettle();

    expect(find.text('Delete “Jeremiah Plan”?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    final doc = firestore.collection('groups').doc(groupId);
    expect((await doc.get()).exists, isFalse);
    expect(find.text('Together'), findsNothing);
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
    await tester.pump();
    expect(find.byType(PlansHubSkeleton), findsOneWidget);

    await tester.pumpAndSettle(const Duration(milliseconds: 1200));
    expect(find.byType(PlansHubSkeleton), findsNothing);
  });
}

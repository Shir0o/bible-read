// Create plan (#988): the rebuilt page keeps every creation path working —
// solo, with a group (which creates the Group), editing a plan in place, and
// a Starting point (ADR-0005).
//
// Runs the real page over FakeFirebaseFirestore and asserts on the data each
// path writes, not on layout.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/reading_plan_progress.dart';
import 'package:bible_read/pages/create_plan_page.dart';
import 'package:bible_read/pages/group_invite_page.dart';
import 'package:bible_read/pages/group_members_page.dart';
import 'package:bible_read/pages/plan_detail_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/reading_plan_service.dart';
import 'package:bible_read/widgets/group_plan_keys.dart';

import '../helpers/stub_vibration_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late ReadingPlanService planService;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    planService = ReadingPlanService(firestore: firestore);
  });

  void useTallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpNewPlan(
    WidgetTester tester, {
    PlanAudience initialAudience = PlanAudience.solo,
  }) async {
    useTallView(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: CreatePlanPage(
          firestore: firestore,
          auth: auth,
          groupService: GroupService(firestore: firestore),
          vibrationService: const StubVibrationService(),
          initialAudience: initialAudience,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<String> onlyPlanId() async =>
      (await firestore.collection('custom_plans').get()).docs.single.id;

  Future<UserPlanProgress> progressOf(String planId) async {
    final doc = await firestore
        .collection('users')
        .doc('u1')
        .collection('plan_progress')
        .doc(planId)
        .get();
    return UserPlanProgress.fromFirestore(doc);
  }

  testWidgets('solo: a two-year plan in order is saved and started', (
    tester,
  ) async {
    await pumpNewPlan(tester);

    await tester.enterText(
      find.byKey(const Key('create_plan_title')),
      'morning light',
    );
    await tester.tap(find.byKey(const Key('create_plan_length_inc')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start plan'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final plan = await planService.getPlanById(await onlyPlanId());
    expect(plan!.title, 'Morning Light');
    expect(plan.config!['type'], 'sequential');
    expect(plan.config!['years'], 2);
    expect(plan.config!['endDate'], isNull);
    expect(plan.schedule.first.readings.first, 'Genesis 1');

    final progress = await progressOf(plan.id);
    expect(progress.completedDays, isEmpty);
    expect((await firestore.collection('groups').get()).docs, isEmpty);
    expect(find.byType(PlanDetailPage), findsOneWidget);
  });

  testWidgets('with a group: the Group and its Shared plan are created', (
    tester,
  ) async {
    // "Create a group" entry points open the form on With a group.
    await pumpNewPlan(tester, initialAudience: PlanAudience.group);

    await tester.enterText(
      find.byKey(const Key('create_plan_title')),
      'Thursday morning group',
    );
    await tester.tap(find.text('New Testament'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start group plan'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final group = (await firestore.collection('groups').get()).docs.single;
    expect(group.data()['name'], 'Thursday morning group');
    expect(group.data()['ownerUid'], 'u1');
    expect(
      (await group.reference.collection('schedule').get()).docs,
      isNotEmpty,
    );
    expect((group.data()['planConfig'] as Map)['books'], contains('Genesis'));
    // A Shared plan is the Group's schedule — no personal plan is written.
    expect((await firestore.collection('custom_plans').get()).docs, isEmpty);
    // The new group offers its invite first, then lands in the group.
    expect(find.byType(GroupInvitePage), findsOneWidget);
    await tester.tap(find.byKey(const Key('group_invite_done')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(GroupMembersPage), findsOneWidget);
  });

  testWidgets(
      'Starting point: days up to the chapter are marked and the '
      'start shifts so it lands on today', (tester) async {
    await pumpNewPlan(tester);

    await tester.enterText(
      find.byKey(const Key('create_plan_title')),
      'Carry On',
    );
    await tester.tap(find.byKey(const Key('create_plan_starting_point')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GroupPlanKeys.startSheetChapter(5)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GroupPlanKeys.startSheetCta));
    await tester.pumpAndSettle();
    expect(find.text('Genesis 5'), findsOneWidget);

    await tester.tap(find.text('Start plan'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // A one-year plan in order reads Genesis 1–4 on day 1 and 5–8 on day 2.
    final progress = await progressOf(await onlyPlanId());
    expect(progress.completedDays, [1, 2]);
    final now = DateTime.now();
    expect(
      progress.startDate,
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1)),
    );
  });

  testWidgets('edit: the same page saves changes in place', (tester) async {
    // An existing plan made through this page, two days in.
    await pumpNewPlan(tester);
    await tester.enterText(
      find.byKey(const Key('create_plan_title')),
      'Morning Light',
    );
    await tester.tap(find.text('Start plan'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    final planId = await onlyPlanId();
    await planService.markDayComplete('u1', planId, 1);
    await planService.markDayComplete('u1', planId, 2);
    final plan = await planService.getPlanById(planId);
    final progress = await progressOf(planId);

    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => CreatePlanPage(
                    firestore: firestore,
                    auth: auth,
                    vibrationService: const StubVibrationService(),
                    editingPlan: plan,
                    editingProgress: progress,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Same page, edit copy; the audience and the dates are fixed.
    expect(find.text('Edit plan'), findsOneWidget);
    expect(find.text("Who's reading"), findsNothing);
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.text('Morning Light'), findsOneWidget);
    await tester.tap(find.byKey(const Key('create_plan_start_date')));
    await tester.tap(find.byKey(const Key('create_plan_starting_point')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.byKey(GroupPlanKeys.startSheet), findsNothing);

    await tester.enterText(
      find.byKey(const Key('create_plan_title')),
      'Evening Light',
    );
    await tester.tap(find.text('New Testament'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    final saved =
        (await firestore.collection('custom_plans').doc(planId).get()).data()!;
    expect(saved['title'], 'Evening Light');
    expect((saved['config'] as Map)['type'], 'ntOnly');
    expect((saved['schedule'] as List).first['readings'].first, 'Matthew 1');
    // Progress is untouched by the edit.
    final after = await progressOf(planId);
    expect(after.completedDays, [1, 2]);
    expect(after.startDate, progress.startDate);
  });

  testWidgets(
      'first-day pace: 1 chapter on Day 1, 2 chapters on remaining days', (
    tester,
  ) async {
    await pumpNewPlan(tester);

    await tester.enterText(
      find.byKey(const Key('create_plan_title')),
      'Two Chapters A Day',
    );
    // Expand "Choose books"
    await tester.tap(find.text('Choose books'));
    await tester.pumpAndSettle();

    // Select "Chapters a day"
    await tester.tap(find.text('Chapters a day'));
    await tester.pumpAndSettle();

    // Chapters a day defaults to 3; decrement to 2
    await tester.tap(find.byKey(const Key('create_plan_chapters_dec')));
    await tester.pumpAndSettle();

    // "First day" option appears when chaptersPerDay > 1; decrement first day to 1
    expect(find.text('First day'), findsOneWidget);
    await tester.tap(find.byKey(const Key('create_plan_first_day_dec')));
    await tester.pumpAndSettle();
    expect(find.text('1 chapter on day one'), findsOneWidget);

    await tester.tap(find.text('Start plan'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final plan = await planService.getPlanById(await onlyPlanId());
    expect(plan!.config!['customChaptersPerDay'], 2);
    expect(plan.config!['firstDayChapters'], 1);
    expect(plan.schedule[0].readings, ['Genesis 1']);
    expect(plan.schedule[1].readings, ['Genesis 2', 'Genesis 3']);
    expect(plan.schedule[2].readings, ['Genesis 4', 'Genesis 5']);
  });
}

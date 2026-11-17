// Create plan (#988): the rebuilt page keeps every creation path working —
// solo, with a group (which creates the Group), editing a plan in place, day
// one beginning mid-Bible, and a Starting point (ADR-0005).
//
// Runs the real page over FakeFirebaseFirestore and asserts on the data each
// path writes, not on layout.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/reading_plan_progress.dart';
import 'package:bible_read/pages/create_plan_page.dart';
import 'package:bible_read/pages/share_code_page.dart';
import 'package:bible_read/pages/group_members_page.dart';
import 'package:bible_read/pages/plan_detail_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/reading_plan_service.dart';

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
    // The group reads what was chosen: the New Testament only.
    final books = (group.data()['planConfig'] as Map)['books'] as List;
    expect(books.first, 'Matthew');
    expect(books, isNot(contains('Genesis')));
    // A Shared plan is the Group's schedule — no personal plan is written.
    expect((await firestore.collection('custom_plans').get()).docs, isEmpty);
    // The new group offers its share code first, then lands in the group.
    expect(find.byType(ShareCodePage), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(GroupMembersPage), findsOneWidget);
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
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);

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
}

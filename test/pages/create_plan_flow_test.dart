import 'package:bible_read/pages/create_plan_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/reading_plan_service.dart';
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

/// The creation flow (#809): one form, entered straight from Path, that asks
/// what to read and over how long first and who is reading as a field.
void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late ReadingPlanService planService;
  late GroupService groupService;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    planService = ReadingPlanService(firestore: firestore);
    groupService = GroupService(firestore: firestore);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: CreatePlanPage(
          firestore: firestore,
          auth: auth,
          groupService: groupService,
          vibrationService: const _StubVibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('just you creates a solo plan with no group', (tester) async {
    await pumpPage(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Plan Title').first,
      'Morning Light',
    );
    await scrollTo(tester, find.text('WHO IS READING'));

    // The default answer is "Just you" — no group name field, no group.
    expect(find.byKey(const Key('create_plan_group_name')), findsNothing);

    await tester.tap(find.text('Start My Plan'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    // The plan exists as a personal plan and was auto-started.
    final plans = await firestore.collection('custom_plans').get();
    expect(plans.docs, hasLength(1));
    expect(plans.docs.single.data()['title'], 'Morning Light');
    final planId = plans.docs.single.id;

    final progress = await firestore
        .collection('users')
        .doc('u1')
        .collection('plan_progress')
        .doc(planId)
        .get();
    expect(progress.exists, isTrue);

    // No group was created.
    expect((await firestore.collection('groups').get()).docs, isEmpty);

    // The flow lands the reader in the plan's detail page.
    expect(find.text('Morning Light'), findsWidgets);
  });

  testWidgets('with a group takes a group name and creates the group and '
      'the shared plan together', (tester) async {
    await pumpPage(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Plan Title').first,
      'Jonah Together',
    );
    await scrollTo(tester, find.text('WHO IS READING'));

    await tester.tap(find.text('With a group'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('create_plan_group_name')),
      'Thursday morning group',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create plan together'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1500));

    // The group exists, owned by the reader, with them as its first member.
    final groups = await firestore.collection('groups').get();
    expect(groups.docs, hasLength(1));
    final group = groups.docs.single;
    expect(group.data()['name'], 'Thursday morning group');
    expect(group.data()['ownerUid'], 'u1');
    final member = await group.reference.collection('members').doc('u1').get();
    expect(member.exists, isTrue);

    // The shared plan is the group's schedule — generated, persisted, and
    // carrying the configuration it was generated from.
    final schedule = await group.reference.collection('schedule').get();
    expect(schedule.docs, isNotEmpty);
    expect(group.data()['planConfig'], isNotNull);
    expect((group.data()['planConfig'] as Map)['books'], contains('Genesis'));

    // A join code was assigned so the group is shareable immediately.
    expect(group.data()['joinCode'], isNotEmpty);

    // The flow lands the reader in the group.
    expect(find.text('Thursday morning group'), findsWidgets);
  });

  testWidgets('a newly created solo plan appears in the Path list '
      'immediately', (tester) async {
    await pumpPage(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Plan Title').first,
      'Morning Light',
    );
    await scrollTo(tester, find.text('WHO IS READING'));
    await tester.tap(find.text('Start My Plan'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    // Reload the hub the way PlansHub does on returning from the flow.
    final hubPlan = await planService.getPlanById(
      (await firestore.collection('custom_plans').get()).docs.single.id,
      userId: 'u1',
    );
    expect(hubPlan, isNotNull);
    expect(hubPlan!.title, 'Morning Light');
    final active = await planService.getActivePlans('u1').first;
    expect(active.map((p) => p.planId), contains(hubPlan.id));
  });

  testWidgets('with a group requires a group name', (tester) async {
    await pumpPage(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Plan Title').first,
      'Jonah Together',
    );
    await scrollTo(tester, find.text('WHO IS READING'));

    await tester.tap(find.text('With a group'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create plan together'));
    await tester.pumpAndSettle();

    expect(find.text('Please name your group.'), findsOneWidget);
    expect((await firestore.collection('groups').get()).docs, isEmpty);
  });
}
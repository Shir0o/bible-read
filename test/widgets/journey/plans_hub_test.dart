import 'package:bible_read/pages/adjust_pace_page.dart';
import 'package:bible_read/pages/create_plan_page.dart';
import 'package:bible_read/models/group.dart';
import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/widgets/journey/plans_hub.dart';
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

    await tester.tap(find.byTooltip('Adjust pace'));
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
  testWidgets(
      'leaving a plan archives it and the archive keeps restore '
      'and permanent delete reachable', (tester) async {
    await pumpPage(tester);

    // Leave = archive: the inline confirm flow on the plan card.
    await tester.tap(find.byTooltip('Leave plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Leave plan'));
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
}

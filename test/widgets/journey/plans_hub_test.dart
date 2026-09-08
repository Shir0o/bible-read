import 'package:bible_read/pages/create_plan_page.dart';
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
 }

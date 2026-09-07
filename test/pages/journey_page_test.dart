import 'package:bible_read/pages/journey_page.dart';
import 'package:bible_read/widgets/journey/consistency_calendar.dart';
import 'package:bible_read/widgets/journey/plans_hub.dart';
import 'package:bible_read/widgets/app_header.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/services/reading_plan_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MockFirebaseAuth auth;
  late FakeFirebaseFirestore firestore;

  setUp(() {
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    firestore = FakeFirebaseFirestore();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: JourneyPage(
          auth: auth,
          firestore: firestore,
          vibrationService: const VibrationService(),
          dateProvider: DateTime.now,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));
  }

  testWidgets('the tab carries the plan hub, tiles and calendar', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.byType(AppHeader), findsOneWidget);
    expect(find.byType(PlansHub), findsOneWidget);
    expect(find.byType(ConsistencyCalendar), findsOneWidget);
    expect(find.text('Shown up'), findsOneWidget);
    expect(find.text('Showing up'), findsOneWidget);
  });

  testWidgets('solo and shared plans list together on the tab', (
    tester,
  ) async {
    const plan = ReadingPlan(
      id: 'p1',
      title: 'Morning Light',
      description: '',
      durationDays: 2,
      tags: [],
      schedule: [
        ReadingPlanDay(day: 1, readings: ['Gen 1']),
        ReadingPlanDay(day: 2, readings: ['Gen 2']),
      ],
    );
    await firestore.collection('custom_plans').doc('p1').set({
      ...plan.toJson(),
      'userId': 'u1',
    });
    await ReadingPlanService(firestore: firestore)
        .startPlan('u1', 'p1', startDate: DateTime.now());
    final groupRef = firestore.collection('groups').doc('g1');
    await groupRef.set({
      'name': 'Evening Circle',
      'ownerUid': 'u2',
      'memberCount': 2,
    });
    await groupRef.collection('members').doc('u1').set({
      'uid': 'u1',
      'role': 'member',
    });
    await groupRef.collection('members').doc('u2').set({
      'uid': 'u2',
      'role': 'owner',
    });

    await pumpPage(tester);

    expect(find.text('Morning Light'), findsOneWidget);
    expect(find.text('Evening Circle'), findsOneWidget);
    expect(find.text('On your own'), findsOneWidget);
    expect(find.text('Together'), findsOneWidget);
  });

  testWidgets(
      'a reader with no plan sees an invitation and their '
      'showing-up record', (tester) async {
    await pumpPage(tester);

    expect(find.text('No active plans yet'), findsOneWidget);
    expect(find.text('Start a plan to give your reading a gentle rhythm.'),
        findsOneWidget);
    expect(find.text('Enroll in a new plan'), findsOneWidget);
    // The Showing-up record renders beside the invitation.
    expect(find.text('Shown up'), findsOneWidget);
    expect(find.text('Day streak'), findsOneWidget);
    expect(find.byType(ConsistencyCalendar), findsOneWidget);
  });
}

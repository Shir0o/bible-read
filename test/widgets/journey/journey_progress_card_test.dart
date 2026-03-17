import 'dart:async';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/models/reading_plan_progress.dart';
import 'package:bible_read/pages/plan_detail_page.dart';
import 'package:bible_read/services/reading_plan_service.dart';
import 'package:bible_read/widgets/journey/journey_progress_card.dart';
import 'package:bible_read/widgets/skeleton.dart';

import '../../helpers/pump_app.dart';

class MockReadingPlanService extends Mock implements ReadingPlanService {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {
  @override
  String get uid => 'test_uid';
}

class MockNavigatorObserver extends Mock implements NavigatorObserver {}

class FakeRoute extends Fake implements Route {}

void main() {
  late MockReadingPlanService readingPlanService;
  late MockFirebaseAuth auth;
  late MockUser user;
  late FakeFirebaseFirestore fakeFirestore;

  setUpAll(() {
    registerFallbackValue(FakeRoute());
  });

  setUp(() {
    readingPlanService = MockReadingPlanService();
    auth = MockFirebaseAuth();
    user = MockUser();
    fakeFirestore = FakeFirebaseFirestore();

    when(() => auth.currentUser).thenReturn(user);

    when(() =>
            readingPlanService.getAvailablePlans(userId: any(named: 'userId')))
        .thenAnswer((_) async => []);
    when(() => readingPlanService.getActivePlans(any()))
        .thenAnswer((_) => Stream.value([]));
  });

  Widget buildSubject({NavigatorObserver? navigatorObserver}) {
    return JourneyProgressCard(
      firestore: fakeFirestore,
      auth: auth,
      readingPlanService: readingPlanService,
    );
  }

  testWidgets('renders loading state initially', (tester) async {
    when(() =>
            readingPlanService.getAvailablePlans(userId: any(named: 'userId')))
        .thenAnswer((_) => Completer<List<ReadingPlan>>().future);

    await tester.pumpApp(buildSubject());

    expect(find.byType(Skeleton), findsWidgets);
    expect(find.text('Start a Reading Plan'), findsNothing);
  });

  testWidgets('renders no active plan card when user has no plans',
      (tester) async {
    when(() =>
            readingPlanService.getAvailablePlans(userId: any(named: 'userId')))
        .thenAnswer((_) async => []);
    when(() => readingPlanService.getActivePlans('test_uid'))
        .thenAnswer((_) => Stream.value([]));

    await tester.pumpApp(buildSubject());
    await tester.pumpAndSettle();

    expect(find.text('Start a Reading Plan'), findsOneWidget);
    expect(find.text('Create Plan'), findsOneWidget);
  });

  testWidgets('renders active plan card when user has an active plan',
      (tester) async {
    final plan = ReadingPlan(
      id: 'plan_1',
      title: 'Bible in a Year',
      description: 'Read the bible in 365 days',
      durationDays: 365,
      tags: [],
      schedule: [],
    );

    final progress = UserPlanProgress(
      planId: 'plan_1',
      userId: 'test_uid',
      completedDays: [1, 2, 3],
      startDate: DateTime.now(),
      lastReadDate: DateTime.now(),
    );

    when(() =>
            readingPlanService.getAvailablePlans(userId: any(named: 'userId')))
        .thenAnswer((_) async => [plan]);
    when(() => readingPlanService.getActivePlans('test_uid'))
        .thenAnswer((_) => Stream.value([progress]));

    await tester.pumpApp(buildSubject());
    await tester.pumpAndSettle();

    expect(find.text('Bible in a Year'), findsOneWidget);
    expect(find.text('Day 4'), findsOneWidget);
    expect(find.text('of 365 • Personal Plan'), findsOneWidget);
    expect(find.text('0% Completed'), findsOneWidget);
  });

  testWidgets('navigates to plan detail on tap', (tester) async {
    final plan = ReadingPlan(
      id: 'plan_1',
      title: 'Bible in a Year',
      description: 'Desc',
      durationDays: 365,
      tags: [],
      schedule: [],
    );
    final progress = UserPlanProgress(
      planId: 'plan_1',
      userId: 'test_uid',
      completedDays: [],
      startDate: DateTime.now(),
      lastReadDate: DateTime.now(),
    );

    when(() =>
            readingPlanService.getAvailablePlans(userId: any(named: 'userId')))
        .thenAnswer((_) async => [plan]);
    when(() => readingPlanService.getActivePlans('test_uid'))
        .thenAnswer((_) => Stream.value([progress]));

    final observer = MockNavigatorObserver();
    await tester.pumpApp(buildSubject(navigatorObserver: observer));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue Reading'));
    await tester.pumpAndSettle();

    // verify(() => observer.didPush(any(), any())).called(1);
    expect(find.byType(PlanDetailPage), findsOneWidget);
  });

  testWidgets('shows Review Plan when completed', (tester) async {
    final plan = ReadingPlan(
      id: 'plan_1',
      title: 'Short Plan',
      description: 'Desc',
      durationDays: 2,
      tags: [],
      schedule: [],
    );
    final progress = UserPlanProgress(
      planId: 'plan_1',
      userId: 'test_uid',
      completedDays: [1, 2],
      startDate: DateTime.now(),
      lastReadDate: DateTime.now(),
    );

    when(() =>
            readingPlanService.getAvailablePlans(userId: any(named: 'userId')))
        .thenAnswer((_) async => [plan]);
    when(() => readingPlanService.getActivePlans('test_uid'))
        .thenAnswer((_) => Stream.value([progress]));

    await tester.pumpApp(buildSubject());
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Review Plan'), findsOneWidget);
  });
}

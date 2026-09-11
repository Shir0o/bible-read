import 'package:bible_read/models/group.dart';
import 'package:bible_read/models/group_member_progress.dart';
import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/pages/plan_detail_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockGroupService extends Mock implements GroupService {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockVibrationService extends Mock implements VibrationService {}

class MockUser extends Mock implements User {}

class MockGroup extends Mock implements Group {}

class FakeGroupSchedule extends Fake implements GroupSchedule {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeGroupSchedule());
  });

  late MockGroupService mockGroupService;
  late MockFirebaseAuth mockAuth;
  late MockVibrationService mockVibrationService;
  late MockUser mockUser;
  late FakeFirebaseFirestore fakeFirestore;
  late Group testGroup;

  setUp(() {
    mockGroupService = MockGroupService();
    mockAuth = MockFirebaseAuth();
    mockVibrationService = MockVibrationService();
    mockUser = MockUser();
    fakeFirestore = FakeFirebaseFirestore();

    testGroup = const Group(
      id: 'test_group',
      name: 'Test Group',
      ownerUid: 'owner_uid',
      memberCount: 5,
    );

    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.uid).thenReturn('test_uid');
    when(() => mockGroupService.firestore).thenReturn(fakeFirestore);
    when(
      () => mockGroupService.userProgressForGroup(any(), any()),
    ).thenAnswer((_) => Stream.value(<String, int>{}));
    when(
      () => mockGroupService.memberDailyCompletion(
        any(),
        date: any(named: 'date'),
      ),
    ).thenAnswer((_) => Stream.value(<GroupMemberProgressData>[]));
  });

  Widget createWidgetUnderTest({bool isMember = true}) {
    return MaterialApp(
      home: PlanDetailPage(
        group: testGroup,
        groupService: mockGroupService,
        auth: mockAuth,
        vibrationService: mockVibrationService,
        isMember: isMember,
      ),
    );
  }

  testWidgets('PlanDetailPage renders list of schedules and shared badge', (
    tester,
  ) async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final yesterday = todayDate.subtract(const Duration(days: 1));
    final tomorrow = todayDate.add(const Duration(days: 1));

    final schedules = [
      GroupSchedule(date: yesterday, chapters: ['Genesis 1']),
      GroupSchedule(date: todayDate, chapters: ['Genesis 2']),
      GroupSchedule(date: tomorrow, chapters: ['Genesis 3']),
    ];

    when(
      () => mockGroupService.schedule('test_group'),
    ).thenAnswer((_) => Stream.value(schedules));

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Redesigned schedule (ScheduleScreenView): summary card eyebrow + full
    // schedule list + gentle catch-up tray for the overdue reading.
    expect(find.text('TEST GROUP'), findsOneWidget);
    expect(find.text('Full schedule'), findsOneWidget);
    expect(find.text('Catch up at your own pace'), findsOneWidget);

    // Shared plan badge
    expect(find.text('Shared plan'), findsOneWidget);
    expect(find.text('5 readers on this schedule'), findsOneWidget);

    // Genesis 1 (overdue) appears in the catch-up tray and the list;
    // Genesis 2 (current) appears in the "with your group" anchor and the list;
    // Genesis 3 (upcoming) appears only in the list.
    expect(find.text('Genesis 1'), findsWidgets);
    expect(find.text('Genesis 2'), findsWidgets);
    expect(find.text('Genesis 3'), findsOneWidget);
  });

  testWidgets('PlanDetailPage handles empty schedule in group mode', (
    tester,
  ) async {
    when(
      () => mockGroupService.schedule('test_group'),
    ).thenAnswer((_) => Stream.value([]));

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    expect(find.text('No schedule available'), findsOneWidget);
  });

  testWidgets(
      'tapping reading toggle in group mode calls groupService.toggleReadStatus',
      (
    tester,
  ) async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    final schedules = [
      GroupSchedule(date: todayDate, chapters: ['Genesis 2']),
    ];

    when(
      () => mockGroupService.schedule('test_group'),
    ).thenAnswer((_) => Stream.value(schedules));
    when(
      () => mockGroupService.toggleReadStatus(
        groupId: any(named: 'groupId'),
        uid: any(named: 'uid'),
        schedule: any(named: 'schedule'),
        read: any(named: 'read'),
      ),
    ).thenAnswer((_) async => true);
    when(() => mockVibrationService.lightImpact()).thenAnswer((_) async {});

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Tap "I read this with the group" button on today's anchor card
    expect(find.text('I read this with the group'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('I read this with the group'));
      await Future.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    verify(
      () => mockGroupService.toggleReadStatus(
        groupId: 'test_group',
        uid: 'test_uid',
        schedule: any(named: 'schedule'),
        read: true,
      ),
    ).called(1);
  });

  testWidgets('month-burst marking marks past group schedules up to today', (
    tester,
  ) async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final yesterday = todayDate.subtract(const Duration(days: 1));

    final schedules = [
      GroupSchedule(date: yesterday, chapters: ['Genesis 1']),
      GroupSchedule(date: todayDate, chapters: ['Genesis 2']),
    ];

    when(
      () => mockGroupService.schedule('test_group'),
    ).thenAnswer((_) => Stream.value(schedules));
    when(
      () => mockGroupService.toggleReadStatus(
        groupId: any(named: 'groupId'),
        uid: any(named: 'uid'),
        schedule: any(named: 'schedule'),
        read: any(named: 'read'),
      ),
    ).thenAnswer((_) async => true);
    when(() => mockVibrationService.lightImpact()).thenAnswer((_) async {});

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Verify "Mark month" button is present and tap it
    final markMonthFinder = find.text('Mark month');
    expect(markMonthFinder, findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(markMonthFinder);
      await Future.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    // Both yesterday and today are up to today, so both should be marked
    verify(
      () => mockGroupService.toggleReadStatus(
        groupId: 'test_group',
        uid: 'test_uid',
        schedule: any(named: 'schedule'),
        read: true,
      ),
    ).called(2);
  });
}

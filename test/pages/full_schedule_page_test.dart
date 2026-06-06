import 'package:bible_read/models/group.dart';
import 'package:bible_read/models/group_member_progress.dart';
import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/pages/full_schedule_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockGroupService extends Mock implements GroupService {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockVibrationService extends Mock implements VibrationService {}

class MockUser extends Mock implements User {}

class MockGroup extends Mock implements Group {}

void main() {
  late MockGroupService mockGroupService;
  late MockFirebaseAuth mockAuth;
  late MockVibrationService mockVibrationService;
  late MockUser mockUser;
  late Group testGroup;

  setUp(() {
    mockGroupService = MockGroupService();
    mockAuth = MockFirebaseAuth();
    mockVibrationService = MockVibrationService();
    mockUser = MockUser();

    testGroup = Group(
      id: 'test_group',
      name: 'Test Group',
      ownerUid: 'owner_uid',
      memberCount: 1,
    );

    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.uid).thenReturn('test_uid');
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

  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: FullSchedulePage(
        group: testGroup,
        groupService: mockGroupService,
        auth: mockAuth,
        vibrationService: mockVibrationService,
      ),
    );
  }

  testWidgets('FullSchedulePage renders list of schedules', (tester) async {
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

    // Genesis 1 (overdue) appears in the catch-up tray and the list;
    // Genesis 2 (current) appears in the "with your group" anchor and the list;
    // Genesis 3 (upcoming) appears only in the list.
    expect(find.text('Genesis 1'), findsWidgets);
    expect(find.text('Genesis 2'), findsWidgets);
    expect(find.text('Genesis 3'), findsOneWidget);
  });

  testWidgets('FullSchedulePage handles empty schedule', (tester) async {
    when(
      () => mockGroupService.schedule('test_group'),
    ).thenAnswer((_) => Stream.value([]));

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    expect(find.text('No schedule available'), findsOneWidget);
  });
}

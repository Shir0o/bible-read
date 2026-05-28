import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/widgets/group_progress_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/models/group_member_progress.dart';

class MockGroupService extends Mock implements GroupService {}

void main() {
  late MockGroupService mockGroupService;

  setUp(() {
    mockGroupService = MockGroupService();
  });

  testWidgets('GroupProgressCard displays correct percentage and status', (
    tester,
  ) async {
    final schedule = [
      GroupSchedule(
        date: DateTime(2026, 1, 1),
        chapters: ['Genesis 1', 'Genesis 2'],
      ),
      GroupSchedule(date: DateTime(2026, 1, 2), chapters: ['Genesis 3']),
    ];

    // Total chapters = 3
    // Today is Jan 1, expected completed = 2 (Genesis 1, 2)
    final currentDate = DateTime(2026, 1, 1);

    when(() => mockGroupService.memberOverallCompletion('g1')).thenAnswer(
      (_) => Stream.value([
        const GroupMemberProgressData(
          uid: 'u1',
          name: 'User 1',
          completion: 0.7, // 0.7 > 0.66...
        ),
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupProgressCard(
            groupId: 'g1',
            schedule: schedule,
            groupService: mockGroupService,
            currentDate: currentDate,
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('70%'), findsOneWidget);
    expect(find.text('On Track'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('GroupProgressCard displays Behind status when progress is low', (
    tester,
  ) async {
    final schedule = [
      GroupSchedule(
        date: DateTime(2026, 1, 1),
        chapters: ['Genesis 1', 'Genesis 2'],
      ),
      GroupSchedule(date: DateTime(2026, 1, 2), chapters: ['Genesis 3']),
    ];

    // Total chapters = 3
    // Today is Jan 2, expected completed = 3
    final currentDate = DateTime(2026, 1, 2);

    when(() => mockGroupService.memberOverallCompletion('g1')).thenAnswer(
      (_) => Stream.value([
        const GroupMemberProgressData(
          uid: 'u1',
          name: 'User 1',
          completion: 0.33, // 1/3 ≈ 0.33
        ),
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupProgressCard(
            groupId: 'g1',
            schedule: schedule,
            groupService: mockGroupService,
            currentDate: currentDate,
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('33%'), findsOneWidget);
    expect(find.text('Behind'), findsOneWidget);
  });
}

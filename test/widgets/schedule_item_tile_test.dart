import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/widgets/schedule_item_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Date and chapter list render correctly', (tester) async {
    final schedule = GroupSchedule(
      date: DateTime(2023, 5, 10),
      chapters: const ['Genesis 1', 'Genesis 2'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ScheduleItemTile(schedule: schedule)),
      ),
    );

    expect(find.text('2023-05-10'), findsOneWidget);
    expect(find.text('Genesis 1, Genesis 2'), findsOneWidget);
  });

  testWidgets(
    'Edit button appears only when onEdit is provided and triggers the callback',
    (tester) async {
      final schedule = GroupSchedule(
        date: DateTime(2023, 1, 1),
        chapters: const ['Genesis 1'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ScheduleItemTile(schedule: schedule)),
        ),
      );

      expect(find.byIcon(Icons.edit), findsNothing);

      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScheduleItemTile(
              schedule: schedule,
              onEdit: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.edit), findsOneWidget);
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    },
  );

  testWidgets('shows read checkbox when state provided', (tester) async {
    bool? toggled;
    final schedule = GroupSchedule(
      date: DateTime(2024, 1, 1),
      chapters: const ['Genesis 1'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleItemTile(
            schedule: schedule,
            currentUserRead: false,
            onToggleRead: (value) => toggled = value,
          ),
        ),
      ),
    );

    final checkboxFinder = find.byType(Checkbox);
    expect(checkboxFinder, findsOneWidget);
    await tester.tap(checkboxFinder);
    await tester.pumpAndSettle();
    expect(toggled, isTrue);
  });

  testWidgets('renders per-chapter chips and forwards toggles', (tester) async {
    final toggles = <int, bool>{};
    final schedule = GroupSchedule(
      date: DateTime(2024, 2, 2),
      chapters: const ['Genesis 1', 'Genesis 2'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleItemTile(
            schedule: schedule,
            checkedChapters: {0},
            onToggleChapter: (index, value) => toggles[index] = value,
          ),
        ),
      ),
    );

    expect(find.text('Genesis 1'), findsAtLeastNWidgets(1));
    expect(find.text('Genesis 2'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('Genesis 2').first);
    await tester.pump();

    expect(toggles[1], isTrue);
  });
}

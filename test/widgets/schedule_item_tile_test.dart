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

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScheduleItemTile(schedule: schedule),
      ),
    ));

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

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScheduleItemTile(schedule: schedule),
      ),
    ));

    expect(find.byIcon(Icons.edit), findsNothing);

    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScheduleItemTile(
          schedule: schedule,
          onEdit: () => tapped = true,
        ),
      ),
    ));

    expect(find.byIcon(Icons.edit), findsOneWidget);
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });
}

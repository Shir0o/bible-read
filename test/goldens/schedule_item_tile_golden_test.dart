import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/schedule_item_tile.dart';
import 'package:bible_read/models/group_schedule.dart';
import '../helpers/pump_golden.dart';

void main() {
  final schedule = GroupSchedule(
    date: DateTime(2023, 1, 1),
    chapters: ['Genesis 1', 'Genesis 2'],
  );

  group('ScheduleItemTile Golden Test', () {
    testWidgets('ScheduleItemTile - Light', (tester) async {
      await tester.pumpGolden(
        ScheduleItemTile(schedule: schedule, onTap: () {}),
        brightness: Brightness.light,
      );
      await expectLater(
        find.byType(ScheduleItemTile),
        matchesGoldenFile('goldens/schedule_item_tile_light.png'),
      );
    });

    testWidgets('ScheduleItemTile - Dark', (tester) async {
      await tester.pumpGolden(
        ScheduleItemTile(schedule: schedule, onTap: () {}),
        brightness: Brightness.dark,
      );
      await expectLater(
        find.byType(ScheduleItemTile),
        matchesGoldenFile('goldens/schedule_item_tile_dark.png'),
      );
    });

    testWidgets('ScheduleItemTile - With Chapters Checked', (tester) async {
      await tester.pumpGolden(
        ScheduleItemTile(
          schedule: schedule,
          checkedChapters: {0},
          onToggleChapter: (index, value) {},
          onTap: () {},
        ),
        brightness: Brightness.light,
      );
      await expectLater(
        find.byType(ScheduleItemTile),
        matchesGoldenFile('goldens/schedule_item_tile_checked.png'),
      );
    });
  });
}

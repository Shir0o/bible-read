import 'package:bible_read/services/schedule_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScheduleGenerator', () {
    test('generateSchedule returns empty list for no books', () {
      final schedule = ScheduleGenerator.generateSchedule(
        books: [],
        startDate: DateTime(2023, 1, 1),
        endDate: DateTime(2023, 1, 31),
        isDaily: true,
      );
      expect(schedule, isEmpty);
    });

    test('generateSchedule returns empty list for end date before start date', () {
      final schedule = ScheduleGenerator.generateSchedule(
        books: ['Genesis'],
        startDate: DateTime(2023, 1, 2),
        endDate: DateTime(2023, 1, 1),
        isDaily: true,
      );
      expect(schedule, isEmpty);
    });

    test('generateSchedule distributes chapters correctly', () {
      // Genesis has 50 chapters.
      // 5 days: Jan 1 - Jan 5.
      // Should be ~10 chapters per day.
      final schedule = ScheduleGenerator.generateSchedule(
        books: ['Genesis'],
        startDate: DateTime(2023, 1, 1),
        endDate: DateTime(2023, 1, 5),
        isDaily: true,
      );

      expect(schedule.length, 5);
      int totalChapters = 0;
      for (final s in schedule) {
        totalChapters += s.chapters.length;
      }
      expect(totalChapters, 50);
      expect(schedule.first.chapters.first, 'Genesis 1');
      expect(schedule.last.chapters.last, 'Genesis 50');
    });

    test('generateSchedule respects weekdays only', () {
      // Jan 1 2023 is a Sunday.
      // Jan 2 is Monday.
      // If we run Jan 1 to Jan 2, weekdays only, we should only have schedule for Jan 2.
      final schedule = ScheduleGenerator.generateSchedule(
        books: ['Jude'], // 1 chapter
        startDate: DateTime(2023, 1, 1), // Sun
        endDate: DateTime(2023, 1, 2), // Mon
        isDaily: false,
      );

      expect(schedule.length, 1);
      expect(schedule.first.date.weekday, 1); // Monday
      expect(schedule.first.chapters, ['Jude 1']);
    });
  });
}

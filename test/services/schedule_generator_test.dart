import 'package:bible_read/services/schedule_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScheduleGenerator', () {
    test('generateSchedule returns empty list for no books', () {
      final schedule = ScheduleGenerator.generateSchedule(
        books: [],
        startDate: DateTime(2023, 1, 1),
        endDate: DateTime(2023, 1, 31),
        selectedWeekdays: [1, 2, 3, 4, 5, 6, 7],
      );
      expect(schedule, isEmpty);
    });

    test(
      'generateSchedule returns empty list for end date before start date',
      () {
        final schedule = ScheduleGenerator.generateSchedule(
          books: ['Genesis'],
          startDate: DateTime(2023, 1, 2),
          endDate: DateTime(2023, 1, 1),
          selectedWeekdays: [1, 2, 3, 4, 5, 6, 7],
        );
        expect(schedule, isEmpty);
      },
    );

    test('generateSchedule returns empty list for no selected weekdays', () {
      final schedule = ScheduleGenerator.generateSchedule(
        books: ['Genesis'],
        startDate: DateTime(2023, 1, 1),
        endDate: DateTime(2023, 1, 5),
        selectedWeekdays: [],
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
        selectedWeekdays: [1, 2, 3, 4, 5, 6, 7],
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

    test('generateSchedule respects selected weekdays only', () {
      // Jan 1 2023 is a Sunday (7).
      // Jan 2 is Monday (1).
      // If we run Jan 1 to Jan 2, Mon-Fri only, we should only have schedule for Jan 2.
      final schedule = ScheduleGenerator.generateSchedule(
        books: ['Jude'], // 1 chapter
        startDate: DateTime(2023, 1, 1), // Sun (7)
        endDate: DateTime(2023, 1, 2), // Mon (1)
        selectedWeekdays: [1, 2, 3, 4, 5],
      );

      expect(schedule.length, 1);
      expect(schedule.first.date.weekday, 1); // Monday
      expect(schedule.first.chapters, ['Jude 1']);
    });

    test('generateSchedule respects custom weekday selection', () {
      // Jan 1 2023 is a Sunday (7).
      // Jan 2 is Monday (1).
      // Jan 3 is Tuesday (2).
      // Select Sunday and Tuesday only.
      final schedule = ScheduleGenerator.generateSchedule(
        books: ['Haggai'], // 2 chapters
        startDate: DateTime(2023, 1, 1), // Sun (7)
        endDate: DateTime(2023, 1, 3), // Tue (2)
        selectedWeekdays: [7, 2],
      );

      expect(schedule.length, 2);
      expect(schedule[0].date.weekday, 7); // Sunday
      expect(schedule[1].date.weekday, 2); // Tuesday
    });
  });
}

import '../models/group_schedule.dart';
import 'reference_parser.dart';

class ScheduleGenerator {
  /// Generates a list of [GroupSchedule] items.
  static List<GroupSchedule> generateSchedule({
    required List<String> books,
    required DateTime startDate,
    DateTime? endDate,
    int? fixedChaptersPerDay,
    required List<int> selectedWeekdays,
  }) {
    if (books.isEmpty || selectedWeekdays.isEmpty) {
      return [];
    }

    if (fixedChaptersPerDay == null &&
        (endDate == null || endDate.isBefore(startDate))) {
      return [];
    }

    final scheduleList = <GroupSchedule>[];
    final allChapters = <String>[];
    for (final book in books) {
      final count = ReferenceParser.chapterCount(book) ?? 0;
      for (int i = 1; i <= count; i++) {
        allChapters.add('$book $i');
      }
    }

    if (allChapters.isEmpty) {
      return [];
    }

    // Determine valid reading days
    DateTime d = DateTime(startDate.year, startDate.month, startDate.day);
    final readingDays = <DateTime>[];

    if (fixedChaptersPerDay != null && fixedChaptersPerDay > 0) {
      // Logic for fixed chapters per day:
      // We don't know the end date yet, we keep adding days until chapters are assigned.
      int totalChapters = allChapters.length;
      int daysNeeded = (totalChapters / fixedChaptersPerDay).ceil();

      // Safety break
      int safetyLimit = 365 * 20; // 20 years

      while (readingDays.length < daysNeeded && safetyLimit > 0) {
        safetyLimit--;
        if (selectedWeekdays.contains(d.weekday)) {
          readingDays.add(DateTime(d.year, d.month, d.day));
        }
        d = d.add(const Duration(days: 1));
      }

      int chaptersAssigned = 0;
      for (int i = 0; i < readingDays.length; i++) {
        final date = readingDays[i];
        int count = fixedChaptersPerDay;

        // Don't exceed remaining chapters
        if (chaptersAssigned + count > totalChapters) {
          count = totalChapters - chaptersAssigned;
        }

        if (count > 0) {
          final dailyChapters =
              allChapters.sublist(chaptersAssigned, chaptersAssigned + count);
          scheduleList.add(GroupSchedule(date: date, chapters: dailyChapters));
          chaptersAssigned += count;
        }
      }
    } else {
      // Existing logic for end date calculation:
      // Normalize dates to start of day to ensure consistent comparison
      final end = DateTime(endDate!.year, endDate.month, endDate.day);

      // Safety break
      int safetyLimit = 365 * 10;

      while (!d.isAfter(end) && safetyLimit > 0) {
        safetyLimit--;
        if (selectedWeekdays.contains(d.weekday)) {
          readingDays.add(DateTime(d.year, d.month, d.day));
        }
        d = d.add(const Duration(days: 1));
      }

      if (readingDays.isEmpty) {
        // Fallback: put everything on start date if no days found (e.g. start=end=Saturday and weekdays only)
        readingDays
            .add(DateTime(startDate.year, startDate.month, startDate.day));
      }

      int totalChapters = allChapters.length;
      int chaptersAssigned = 0;

      for (int i = 0; i < readingDays.length; i++) {
        final date = readingDays[i];
        // Remaining chapters / Remaining days
        int remainingDays = readingDays.length - i;
        int remainingChapters = totalChapters - chaptersAssigned;

        if (remainingDays <= 0) break; // Should not happen

        int count = (remainingChapters / remainingDays).ceil();
        if (count > remainingChapters) count = remainingChapters;

        if (count > 0) {
          final dailyChapters =
              allChapters.sublist(chaptersAssigned, chaptersAssigned + count);
          scheduleList.add(GroupSchedule(date: date, chapters: dailyChapters));
          chaptersAssigned += count;
        }
      }
    }

    // Double check if any chapters missed (due to rounding logic, though ceil usually overestimates early)
    int totalChapters = allChapters.length;
    int chaptersAssigned = 0;
    for (final s in scheduleList) {
      chaptersAssigned += s.chapters.length;
    }

    if (chaptersAssigned < totalChapters && scheduleList.isNotEmpty) {
      final last = scheduleList.last;
      final extra = allChapters.sublist(chaptersAssigned);
      scheduleList[scheduleList.length - 1] = GroupSchedule(
        date: last.date,
        chapters: [...last.chapters, ...extra],
      );
    }

    return scheduleList;
  }
}

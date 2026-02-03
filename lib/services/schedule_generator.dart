import '../models/group_schedule.dart';
import 'reference_parser.dart';

class ScheduleGenerator {
  /// Generates a list of [GroupSchedule] items.
  static List<GroupSchedule> generateSchedule({
    required List<String> books,
    required DateTime startDate,
    required DateTime endDate,
    required bool isDaily,
  }) {
    if (books.isEmpty || endDate.isBefore(startDate)) {
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
    DateTime d = startDate;
    final readingDays = <DateTime>[];
    // Normalize dates to start of day to ensure consistent comparison
    final end = DateTime(endDate.year, endDate.month, endDate.day);

    // Safety break
    int safetyLimit = 365 * 10;

    while (!d.isAfter(end) && safetyLimit > 0) {
      safetyLimit--;
      // If isDaily is false (Weekdays only), skip Saturday (6) and Sunday (7)
      if (isDaily || (d.weekday >= 1 && d.weekday <= 5)) {
        readingDays.add(d);
      }
      d = d.add(const Duration(days: 1));
    }

    if (readingDays.isEmpty) {
      // Fallback: put everything on start date if no days found (e.g. start=end=Saturday and weekdays only)
      readingDays.add(startDate);
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
        final dailyChapters = allChapters.sublist(chaptersAssigned, chaptersAssigned + count);
        scheduleList.add(GroupSchedule(date: date, chapters: dailyChapters));
        chaptersAssigned += count;
      }
    }

    // Double check if any chapters missed (due to rounding logic, though ceil usually overestimates early)
    // Actually with ceil, we might finish early.
    // If we finished early, the last days will have 0 chapters. We just won't add schedule entries for them?
    // Or should we spread strictly?
    // The current implementation fills early days more heavily if uneven.

    // If chaptersAssigned < totalChapters (shouldn't happen with ceil), add to last day.
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

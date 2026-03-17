import '../models/reading_plan.dart';
import 'reference_parser.dart';

enum PlanType {
  sequential,
  portions,
  threeOldOneNew,
  otOnly,
  ntOnly,
}

class PlanGenerator {
  /// Generates a reading plan based on the specified type and parameters.
  static ReadingPlan generatePlan({
    required String id,
    required String title,
    required String description,
    required PlanType type,
    int years = 1,
    DateTime? startDate,
    DateTime? endDate,
    List<int>? readingDays, // 1-7 (Mon-Sun)
    List<String>? selectedBooks,
    int? customChaptersPerDay,
    int? customVersesPerDay,
  }) {
    startDate ??= DateTime.now();
    final List<String> allChapters = [];

    // 1. Determine the pool of chapters to read
    if (type == PlanType.otOnly) {
      final otBooks = ReferenceParser.allBooks.take(39);
      for (final book in otBooks) {
        final count = ReferenceParser.chapterCount(book) ?? 0;
        for (int i = 1; i <= count; i++) {
          allChapters.add('$book $i');
        }
      }
    } else if (type == PlanType.ntOnly) {
      final ntBooks = ReferenceParser.allBooks.skip(39);
      for (final book in ntBooks) {
        final count = ReferenceParser.chapterCount(book) ?? 0;
        for (int i = 1; i <= count; i++) {
          allChapters.add('$book $i');
        }
      }
    } else if (selectedBooks != null && selectedBooks.isNotEmpty) {
      for (final book in selectedBooks) {
        final count = ReferenceParser.chapterCount(book) ?? 0;
        for (int i = 1; i <= count; i++) {
          allChapters.add('$book $i');
        }
      }
    } else {
      // Default to whole Bible
      for (final book in ReferenceParser.allBooks) {
        final count = ReferenceParser.chapterCount(book) ?? 0;
        for (int i = 1; i <= count; i++) {
          allChapters.add('$book $i');
        }
      }
    }

    if (allChapters.isEmpty) {
      return ReadingPlan(
        id: id,
        title: title,
        description: description,
        durationDays: 0,
        tags: [type.name],
        schedule: [],
      );
    }

    // 2. Distribute chapters into days
    if (type == PlanType.threeOldOneNew) {
      return _generateThreeOldOneNew(id, title, description, startDate);
    } else if (endDate != null) {
      // Custom end date: calculate duration and chapters per day
      return _generateFixedDuration(
          id, title, description, allChapters, startDate, endDate, readingDays);
    } else if (customChaptersPerDay != null) {
      // Custom amount per day (chapters)
      return _generateFixedPace(id, title, description, allChapters, startDate,
          customChaptersPerDay, readingDays);
    } else if (customVersesPerDay != null) {
      // Custom amount per day (verses) - approximate to chapters
      // Bible has ~31,102 verses / 1,189 chapters ≈ 26 verses per chapter
      final int chaptersPerDay = (customVersesPerDay / 26).ceil().clamp(1, 100);
      return _generateFixedPace(id, title, description, allChapters, startDate,
          chaptersPerDay, readingDays);
    } else {
      // Fixed years (1 or 2)
      final durationDays = years * 365;
      return _generateSequentialOrPortions(
        id,
        title,
        description,
        type,
        allChapters,
        startDate,
        durationDays,
        readingDays,
      );
    }
  }

  static ReadingPlan _generateThreeOldOneNew(
      String id, String title, String description, DateTime startDate) {
    // "To complete the 'Three in the Old and One in the New' schedule in one year,
    // you must read three OT chapters on six days and one NT chapter on five days."
    // OT: 3 chapters * 6 days = 18 chapters/week.
    // NT: 1 chapter * 5 days = 5 chapters/week.
    // Total OT chapters: 929. 929 / 18 = 51.6 weeks.
    // Total NT chapters: 260. 260 / 5 = 52 weeks.
    // This fits roughly in a year.

    final otChapters = <String>[];
    for (final book in ReferenceParser.allBooks.take(39)) {
      final count = ReferenceParser.chapterCount(book) ?? 0;
      for (int i = 1; i <= count; i++) {
        otChapters.add('$book $i');
      }
    }

    final ntChapters = <String>[];
    for (final book in ReferenceParser.allBooks.skip(39)) {
      final count = ReferenceParser.chapterCount(book) ?? 0;
      for (int i = 1; i <= count; i++) {
        ntChapters.add('$book $i');
      }
    }

    final List<ReadingPlanDay> schedule = [];
    int otIdx = 0;
    int ntIdx = 0;
    int day = 1;

    while (otIdx < otChapters.length || ntIdx < ntChapters.length) {
      final List<String> todayReadings = [];

      // OT: 3 chapters on 6 days (let's say Mon-Sat)
      int weekday = ((day - 1) % 7) + 1; // 1=Mon, 7=Sun
      if (weekday <= 6 && otIdx < otChapters.length) {
        for (int i = 0; i < 3 && otIdx < otChapters.length; i++) {
          todayReadings.add(otChapters[otIdx++]);
        }
      }

      // NT: 1 chapter on 5 days (let's say Mon-Fri)
      if (weekday <= 5 && ntIdx < ntChapters.length) {
        todayReadings.add(ntChapters[ntIdx++]);
      }

      if (todayReadings.isNotEmpty) {
        schedule.add(ReadingPlanDay(day: day, readings: todayReadings));
      }
      day++;
    }

    return ReadingPlan(
      id: id,
      title: title,
      description: description,
      durationDays: day - 1,
      tags: ['threeOldOneNew'],
      schedule: schedule,
    );
  }

  static ReadingPlan _generateFixedDuration(
    String id,
    String title,
    String description,
    List<String> allChapters,
    DateTime startDate,
    DateTime endDate,
    List<int>? readingDays,
  ) {
    final List<DateTime> validDates = [];
    DateTime current = startDate;
    final normalizedEnd = DateTime(endDate.year, endDate.month, endDate.day);

    while (!current.isAfter(normalizedEnd)) {
      if (readingDays == null || readingDays.contains(current.weekday)) {
        validDates.add(current);
      }
      current = current.add(const Duration(days: 1));
    }

    final List<ReadingPlanDay> schedule = [];
    if (validDates.isEmpty) return _emptyPlan(id, title, description);

    int chaptersAssigned = 0;
    for (int i = 0; i < validDates.length; i++) {
      int remainingDays = validDates.length - i;
      int remainingChapters = allChapters.length - chaptersAssigned;
      int count = (remainingChapters / remainingDays).ceil();

      final daily =
          allChapters.sublist(chaptersAssigned, chaptersAssigned + count);
      // We use the date relative index as 'day' for the ReadingPlan model
      // or should 'day' be the calendar day since start?
      // ReadingPlan model uses 1-indexed sequential days.
      schedule.add(ReadingPlanDay(day: i + 1, readings: daily));
      chaptersAssigned += count;
    }

    return ReadingPlan(
      id: id,
      title: title,
      description: description,
      durationDays: validDates.length,
      tags: ['custom'],
      schedule: schedule,
    );
  }

  static ReadingPlan _generateFixedPace(
    String id,
    String title,
    String description,
    List<String> allChapters,
    DateTime startDate,
    int chaptersPerDay,
    List<int>? readingDays,
  ) {
    final List<ReadingPlanDay> schedule = [];
    int chaptersAssigned = 0;
    int dayCount = 0;

    while (chaptersAssigned < allChapters.length) {
      dayCount++;
      // Check if this "logical day" should have reading
      // Actually, ReadingPlan model expects sequential days.
      // If user only reads Mon-Fri, Day 1 is Monday, Day 2 is Tuesday...
      // The startDate determines when Day 1 is.

      int count = chaptersPerDay;
      if (chaptersAssigned + count > allChapters.length) {
        count = allChapters.length - chaptersAssigned;
      }

      final daily =
          allChapters.sublist(chaptersAssigned, chaptersAssigned + count);
      schedule.add(ReadingPlanDay(day: dayCount, readings: daily));
      chaptersAssigned += count;
    }

    return ReadingPlan(
      id: id,
      title: title,
      description: description,
      durationDays: dayCount,
      tags: ['custom'],
      schedule: schedule,
    );
  }

  static ReadingPlan _generateSequentialOrPortions(
    String id,
    String title,
    String description,
    PlanType type,
    List<String> allChapters,
    DateTime startDate,
    int durationDays,
    List<int>? readingDays,
  ) {
    if (type == PlanType.portions) {
      return _generatePortions(
          id, title, description, startDate, durationDays, readingDays);
    }

    // Sequential
    final List<ReadingPlanDay> schedule = [];
    int chaptersAssigned = 0;
    for (int i = 0; i < durationDays; i++) {
      int remainingDays = durationDays - i;
      int remainingChapters = allChapters.length - chaptersAssigned;
      int count = (remainingChapters / remainingDays).ceil();

      final daily =
          allChapters.sublist(chaptersAssigned, chaptersAssigned + count);
      schedule.add(ReadingPlanDay(day: i + 1, readings: daily));
      chaptersAssigned += count;
      if (chaptersAssigned >= allChapters.length) break;
    }

    return ReadingPlan(
      id: id,
      title: title,
      description: description,
      durationDays: schedule.length,
      tags: [type.name],
      schedule: schedule,
    );
  }

  static ReadingPlan _generatePortions(
    String id,
    String title,
    String description,
    DateTime startDate,
    int durationDays,
    List<int>? readingDays,
  ) {
    // Portions: OT and NT simultaneously
    final otChapters = <String>[];
    for (final book in ReferenceParser.allBooks.take(39)) {
      final count = ReferenceParser.chapterCount(book) ?? 0;
      for (int i = 1; i <= count; i++) {
        otChapters.add('$book $i');
      }
    }

    final ntChapters = <String>[];
    for (final book in ReferenceParser.allBooks.skip(39)) {
      final count = ReferenceParser.chapterCount(book) ?? 0;
      for (int i = 1; i <= count; i++) {
        ntChapters.add('$book $i');
      }
    }

    final List<ReadingPlanDay> schedule = [];
    int otAssigned = 0;
    int ntAssigned = 0;

    for (int i = 0; i < durationDays; i++) {
      int remainingDays = durationDays - i;
      final todayReadings = <String>[];

      // OT Portion
      int otRemaining = otChapters.length - otAssigned;
      if (otRemaining > 0) {
        int otCount = (otRemaining / remainingDays).ceil();
        todayReadings
            .addAll(otChapters.sublist(otAssigned, otAssigned + otCount));
        otAssigned += otCount;
      }

      // NT Portion
      int ntRemaining = ntChapters.length - ntAssigned;
      if (ntRemaining > 0) {
        int ntCount = (ntRemaining / remainingDays).ceil();
        todayReadings
            .addAll(ntChapters.sublist(ntAssigned, ntAssigned + ntCount));
        ntAssigned += ntCount;
      }

      if (todayReadings.isNotEmpty) {
        schedule.add(ReadingPlanDay(day: i + 1, readings: todayReadings));
      }
      if (otAssigned >= otChapters.length && ntAssigned >= ntChapters.length) {
        break;
      }
    }

    return ReadingPlan(
      id: id,
      title: title,
      description: description,
      durationDays: schedule.length,
      tags: ['portions'],
      schedule: schedule,
    );
  }

  static ReadingPlan _emptyPlan(String id, String title, String description) {
    return ReadingPlan(
      id: id,
      title: title,
      description: description,
      durationDays: 0,
      tags: [],
      schedule: [],
    );
  }
}

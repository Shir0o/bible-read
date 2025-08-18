import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/week_streak_calendar.dart';
import 'package:bible_read/widgets/month_streak_calendar.dart';

void main() {
  const fixedNow = DateTime(2024, 1, 10);
  final fixedSunday =
      fixedNow.subtract(Duration(days: fixedNow.weekday % 7));
  final fixedMonth = DateTime(fixedNow.year, fixedNow.month);

  testWidgets('WeekStreakCalendar renders without interactive day cells', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeekStreakCalendar(
          readDates: <DateTime>{},
          sunday: fixedSunday,
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(WeekStreakCalendar),
        matching: find.byType(IconButton),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('WeekStreakCalendar hides navigation when disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeekStreakCalendar(
          readDates: <DateTime>{},
          sunday: fixedSunday,
          showNavigation: false,
        ),
      ),
    );
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byIcon(Icons.arrow_forward), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('MonthStreakCalendar renders without interactive day cells', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MonthStreakCalendar(
          readDates: <DateTime>{},
          month: fixedMonth,
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(MonthStreakCalendar),
        matching: find.byType(IconButton),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('MonthStreakCalendar hides navigation when disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MonthStreakCalendar(
          readDates: <DateTime>{},
          month: fixedMonth,
          showNavigation: false,
        ),
      ),
    );
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byIcon(Icons.arrow_forward), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('WeekStreakCalendar highlights provided read dates', (
    tester,
  ) async {
    final readDates = {
      DateTime(fixedNow.year, fixedNow.month, fixedNow.day),
      DateTime(fixedNow.year, fixedNow.month, fixedNow.day - 1),
    };
    await tester.pumpWidget(
      MaterialApp(
        home: WeekStreakCalendar(
          readDates: readDates,
          sunday: fixedSunday,
        ),
      ),
    );
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
  });

  testWidgets('MonthStreakCalendar highlights provided read dates', (
    tester,
  ) async {
    final readDates = {
      DateTime(fixedMonth.year, fixedMonth.month, 1),
      DateTime(fixedMonth.year, fixedMonth.month, 2),
    };
    await tester.pumpWidget(
      MaterialApp(
        home: MonthStreakCalendar(
          readDates: readDates,
          month: fixedMonth,
        ),
      ),
    );
    expect(find.byIcon(Icons.circle), findsNWidgets(2));
  });
}

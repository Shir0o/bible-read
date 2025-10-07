import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/week_streak_calendar.dart';
import 'package:bible_read/widgets/month_streak_calendar.dart';

final fixedNow = DateTime(2024, 1, 10);
final fixedSunday = DateTime(2024, 1, 7);
final fixedMonth = DateTime(2024, 1, 1);

void main() {
  testWidgets('WeekStreakCalendar renders without interactive day cells', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: WeekStreakCalendar(
            readDates: <DateTime>{},
            sunday: fixedSunday,
          ),
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
        home: Material(
          child: WeekStreakCalendar(
            readDates: <DateTime>{},
            sunday: fixedSunday,
            showNavigation: false,
          ),
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
        home: Material(
          child: MonthStreakCalendar(
            readDates: <DateTime>{},
            month: fixedMonth,
          ),
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
        home: Material(
          child: MonthStreakCalendar(
            readDates: <DateTime>{},
            month: fixedMonth,
            showNavigation: false,
          ),
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
      fixedNow,
      DateTime(2024, 1, 9),
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: WeekStreakCalendar(
            readDates: readDates,
            sunday: fixedSunday,
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
  });

  testWidgets('MonthStreakCalendar highlights provided read dates', (
    tester,
  ) async {
    final readDates = {
      DateTime(2024, 1, 1),
      DateTime(2024, 1, 2),
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: MonthStreakCalendar(
            readDates: readDates,
            month: fixedMonth,
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.circle), findsNWidgets(2));
  });
}

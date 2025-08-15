import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/week_streak_calendar.dart';
import 'package:bible_read/widgets/month_streak_calendar.dart';

void main() {
  testWidgets('WeekStreakCalendar renders without interactive day cells',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeekStreakCalendar(
          readDates: <DateTime>{},
          sunday: DateTime.now()
              .subtract(Duration(days: DateTime.now().weekday % 7)),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(WeekStreakCalendar),
        matching: find.byType(InkWell),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('WeekStreakCalendar hides navigation when disabled',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeekStreakCalendar(
          readDates: <DateTime>{},
          sunday: DateTime.now()
              .subtract(Duration(days: DateTime.now().weekday % 7)),
          showNavigation: false,
        ),
      ),
    );
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byIcon(Icons.arrow_forward), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('MonthStreakCalendar renders without interactive day cells',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MonthStreakCalendar(
          readDates: <DateTime>{},
          currentMonth: DateTime(DateTime.now().year, DateTime.now().month),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(MonthStreakCalendar),
        matching: find.byType(InkWell),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('MonthStreakCalendar hides navigation when disabled',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MonthStreakCalendar(
          readDates: <DateTime>{},
          currentMonth: DateTime(DateTime.now().year, DateTime.now().month),
          showNavigation: false,
        ),
      ),
    );
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byIcon(Icons.arrow_forward), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('WeekStreakCalendar highlights provided read dates',
      (tester) async {
    final now = DateTime.now();
    final readDates = {
      DateTime(now.year, now.month, now.day),
      DateTime(now.year, now.month, now.day - 1),
    };
    await tester.pumpWidget(
      MaterialApp(
        home: WeekStreakCalendar(
          readDates: readDates,
          sunday: DateTime.now()
              .subtract(Duration(days: DateTime.now().weekday % 7)),
        ),
      ),
    );
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
  });

  testWidgets('MonthStreakCalendar highlights provided read dates',
      (tester) async {
    final now = DateTime.now();
    final readDates = {
      DateTime(now.year, now.month, 1),
      DateTime(now.year, now.month, 2),
    };
    await tester.pumpWidget(
      MaterialApp(
        home: MonthStreakCalendar(
          readDates: readDates,
          currentMonth: DateTime(now.year, now.month),
        ),
      ),
    );
    expect(find.byIcon(Icons.circle), findsNWidgets(2));
  });
}

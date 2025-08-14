import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/week_streak_calendar.dart';
import 'package:bible_read/widgets/month_streak_calendar.dart';

void main() {
  testWidgets('WeekStreakCalendar renders without interactive day cells',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: WeekStreakCalendar(readDates: <DateTime>{}),
      ),
    );
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('MonthStreakCalendar renders without interactive day cells',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MonthStreakCalendar(readDates: <DateTime>{}),
      ),
    );
    expect(find.byType(InkWell), findsNothing);
  });
}

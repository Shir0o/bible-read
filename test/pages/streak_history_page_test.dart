import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/streak_history_page.dart';
import 'package:bible_read/widgets/week_streak_calendar.dart';
import 'package:bible_read/widgets/month_streak_calendar.dart';
import 'package:bible_read/widgets/streak_stats_box.dart';

String _fmt(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _monthName(int month) => const [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ][month - 1];

void main() {
  testWidgets('week and month views render correct day cells', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );

    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({
      'streak': 0,
      'longestStreak': 0,
      'totalReadDays': 0,
      'pastWeekReadDates': <String>[],
      'pastMonthReadDates': <String>[],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: StreakHistoryPage(firestore: firestore, auth: auth),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StreakStatsBox), findsOneWidget);
    expect(
      find.text(
        'Each month includes two automatic grace credits to freeze a missed day. '
        'Every 15-day streak earns one extra credit.',
      ),
      findsOneWidget,
    );

    final weekCal = find.byType(WeekStreakCalendar);
    expect(weekCal, findsOneWidget);
    final weekCells = find.descendant(
      of: weekCal,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Icon &&
            (widget.icon == Icons.check_circle ||
                widget.icon == Icons.radio_button_unchecked),
      ),
    );
    expect(weekCells, findsNWidgets(7));

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();

    final monthCal = find.byType(MonthStreakCalendar);
    expect(monthCal, findsOneWidget);
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final monthCells = find.descendant(
      of: monthCal,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Icon &&
            (widget.icon == Icons.circle ||
                widget.icon == Icons.circle_outlined),
      ),
    );
    expect(monthCells, findsNWidgets(daysInMonth));
  });

  testWidgets('period navigation updates calendar and stats', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );

    final now = DateTime.now();
    final currentWeekStart = now.subtract(Duration(days: now.weekday % 7));
    final prevWeekStart = currentWeekStart.subtract(const Duration(days: 7));

    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({
      'streak': 0,
      'longestStreak': 0,
      'totalReadDays': 0,
      'pastWeekReadDates': [
        _fmt(currentWeekStart),
        _fmt(currentWeekStart.add(const Duration(days: 1))),
      ],
      'pastMonthReadDates': <String>[],
    });

    for (int i = 0; i < 2; i++) {
      final day = currentWeekStart.add(Duration(days: i));
      await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc(_fmt(day))
          .set({'read': true});
    }

    for (int i = 0; i < 3; i++) {
      final day = prevWeekStart.add(Duration(days: i));
      await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc(
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
          )
          .set({'read': true});
    }

    await tester.pumpWidget(
      MaterialApp(
        home: StreakHistoryPage(firestore: firestore, auth: auth),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StreakStatsBox), findsOneWidget);
    final currentLabel =
        'Week of ${currentWeekStart.month}/${currentWeekStart.day}';
    expect(find.text(currentLabel), findsOneWidget);
    expect(find.text('Week reads: 2'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(WeekStreakCalendar),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsNWidgets(2),
    );

    await tester.tap(
      find.descendant(
        of: find.byType(WeekStreakCalendar),
        matching: find.byIcon(Icons.arrow_back),
      ),
    );
    await tester.pumpAndSettle();
    final prevLabel = 'Week of ${prevWeekStart.month}/${prevWeekStart.day}';
    expect(find.text(prevLabel), findsOneWidget);
    expect(find.text('Week reads: 3'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(WeekStreakCalendar),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsNWidgets(3),
    );

    await tester.tap(
      find.descendant(
        of: find.byType(WeekStreakCalendar),
        matching: find.byIcon(Icons.arrow_forward),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(currentLabel), findsOneWidget);
    expect(find.text('Week reads: 2'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(WeekStreakCalendar),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('month navigation updates calendar and stats', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );

    final now = DateTime.now();
    final prevMonthStart = DateTime(now.year, now.month - 1, 1);

    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({
      'streak': 0,
      'longestStreak': 0,
      'totalReadDays': 0,
      'pastWeekReadDates': <String>[],
      'pastMonthReadDates': <String>[],
    });

    for (int i = 0; i < 2; i++) {
      final day = prevMonthStart.add(Duration(days: i));
      await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc(_fmt(day))
          .set({'read': true});
    }

    await tester.pumpWidget(
      MaterialApp(
        home: StreakHistoryPage(firestore: firestore, auth: auth),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();

    final currentLabel = '${now.year} – ${_monthName(now.month)}';
    expect(find.text(currentLabel), findsOneWidget);
    expect(find.text('Month reads: 0'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(MonthStreakCalendar),
        matching: find.byIcon(Icons.arrow_back),
      ),
    );
    await tester.pumpAndSettle();

    final prevLabel =
        '${prevMonthStart.year} – ${_monthName(prevMonthStart.month)}';
    expect(find.text(prevLabel), findsOneWidget);
    expect(find.text('Month reads: 2'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MonthStreakCalendar),
        matching: find.byIcon(Icons.circle),
      ),
      findsNWidgets(2),
    );

    await tester.tap(
      find.descendant(
        of: find.byType(MonthStreakCalendar),
        matching: find.byIcon(Icons.arrow_forward),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(currentLabel), findsOneWidget);
    expect(find.text('Month reads: 0'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MonthStreakCalendar),
        matching: find.byIcon(Icons.circle),
      ),
      findsNothing,
    );
  });
}

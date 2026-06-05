import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/services/catch_up_engine.dart';
import 'package:bible_read/widgets/schedule_preview.dart';

CatchUpStatus _dailyStatus({
  required int days,
  required DateTime start,
  required Set<int> completed,
  required DateTime today,
}) {
  final entries = List.generate(
    days,
    (i) => ScheduleEntry(
      index: i + 1,
      date: DateTime(start.year, start.month, start.day + i),
      readings: ['Genesis ${i + 1}'],
      completed: completed.contains(i + 1),
    ),
  );
  return CatchUpEngine.compute(entries, today: today);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  testWidgets('windows around the resume index, hiding earlier/later readings',
      (tester) async {
    // 20-day plan, started 10 days ago, nothing completed → resume is day 1
    // (first missed). Window of 5 should show days 1..5 and a "more" ellipsis.
    final start = DateTime(2024, 1, 1);
    final status = _dailyStatus(
      days: 20,
      start: start,
      completed: const {},
      today: DateTime(2024, 1, 10),
    );

    await pump(
      tester,
      SchedulePreview(status: status, title: 'My Plan', windowSize: 5),
    );

    // First five readings shown.
    expect(find.text('Genesis 1'), findsOneWidget);
    expect(find.text('Genesis 5'), findsOneWidget);
    // A later reading is hidden behind the ellipsis.
    expect(find.text('Genesis 12'), findsNothing);
    expect(find.textContaining('more'), findsOneWidget);
  });

  testWidgets('shows behind count gently as "to revisit", never red',
      (tester) async {
    final start = DateTime(2024, 1, 1);
    final status = _dailyStatus(
      days: 20,
      start: start,
      completed: const {},
      today: DateTime(2024, 1, 5), // days 1-4 missed, day 5 current
    );

    await pump(tester, SchedulePreview(status: status, title: 'My Plan'));

    expect(find.textContaining('to revisit'), findsOneWidget);
  });

  testWidgets('weekly cadence yields a sensible per-week pace string',
      (tester) async {
    // 6 readings, one per week → "~1 reading/week".
    final entries = List.generate(
      6,
      (i) => ScheduleEntry(
        index: i,
        date: DateTime(2024, 1, 1 + i * 7),
        readings: ['Week ${i + 1}'],
        completed: false,
      ),
    );
    final status = CatchUpEngine.compute(entries, today: DateTime(2024, 1, 1));

    await pump(tester, SchedulePreview(status: status, title: 'Weekly'));

    expect(find.textContaining('reading/week'), findsOneWidget);
  });

  testWidgets('View full schedule action shown only when callback provided',
      (tester) async {
    final status = _dailyStatus(
      days: 5,
      start: DateTime(2024, 1, 1),
      completed: const {},
      today: DateTime(2024, 1, 1),
    );

    await pump(tester, SchedulePreview(status: status, title: 'Plan'));
    expect(find.text('View full schedule'), findsNothing);

    await pump(
      tester,
      SchedulePreview(
        status: status,
        title: 'Plan',
        onViewFull: () {},
      ),
    );
    expect(find.text('View full schedule'), findsOneWidget);
  });
}

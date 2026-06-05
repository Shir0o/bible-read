import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/services/catch_up_engine.dart';
import 'package:bible_read/widgets/catch_up_status_row.dart';

CatchUpStatus _statusFor(List<ScheduleEntry> entries) =>
    CatchUpEngine.compute(entries, today: DateTime(2024, 1, 5));

ScheduleEntry _entry(int index, DateTime date, {bool completed = false}) =>
    ScheduleEntry(
      index: index,
      date: date,
      readings: ['Genesis $index'],
      completed: completed,
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows behind count and catch-up action when behind',
      (tester) async {
    // Two past readings, both unread → 2 behind.
    final status = _statusFor([
      _entry(1, DateTime(2024, 1, 3)),
      _entry(2, DateTime(2024, 1, 4)),
      _entry(3, DateTime(2024, 1, 5)),
    ]);

    await tester.pumpWidget(
      _wrap(CatchUpStatusRow(status: status, onTap: () {})),
    );

    expect(find.textContaining('2 readings behind'), findsOneWidget);
    expect(find.textContaining('Catch up'), findsOneWidget);
  });

  testWidgets('shows on-track copy when in step', (tester) async {
    // All due readings completed → on track.
    final status = _statusFor([
      _entry(1, DateTime(2024, 1, 4), completed: true),
      _entry(2, DateTime(2024, 1, 5), completed: true),
      _entry(3, DateTime(2024, 1, 6)),
    ]);

    await tester.pumpWidget(
      _wrap(CatchUpStatusRow(status: status, onTap: () {})),
    );

    expect(find.textContaining("You're on track"), findsOneWidget);
    expect(find.textContaining('behind'), findsNothing);
  });

  testWidgets('renders nothing for an empty schedule', (tester) async {
    final status = _statusFor(const []);

    await tester.pumpWidget(
      _wrap(CatchUpStatusRow(status: status, onTap: () {})),
    );

    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('invokes onTap when tapped', (tester) async {
    var tapped = false;
    final status = _statusFor([
      _entry(1, DateTime(2024, 1, 3)),
      _entry(2, DateTime(2024, 1, 5)),
    ]);

    await tester.pumpWidget(
      _wrap(CatchUpStatusRow(status: status, onTap: () => tapped = true)),
    );
    await tester.tap(find.byType(CatchUpStatusRow));
    expect(tapped, isTrue);
  });
}

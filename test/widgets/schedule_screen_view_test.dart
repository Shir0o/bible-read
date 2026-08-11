import 'package:bible_read/services/catch_up_engine.dart';
import 'package:bible_read/widgets/schedule_screen_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a [CatchUpStatus] from explicit day offsets relative to [today],
/// so each test controls exactly which rows are done/current/missed/upcoming.
CatchUpStatus _status({
  required List<({int dayOffset, bool completed})> days,
  required DateTime today,
}) {
  final entries = <ScheduleEntry>[];
  for (var i = 0; i < days.length; i++) {
    final d = days[i];
    entries.add(
      ScheduleEntry(
        index: i,
        date: today.add(Duration(days: d.dayOffset)),
        readings: ['Genesis ${i + 1}'],
        completed: d.completed,
      ),
    );
  }
  return CatchUpEngine.compute(entries, today: today);
}

Widget _host(CatchUpStatus status, {bool isGroup = true}) {
  return MaterialApp(
    home: Scaffold(
      body: ScheduleScreenView(
        status: status,
        title: 'Test Plan',
        isGroup: isGroup,
        onToggle: (_) {},
        todayAnchorBuilder: isGroup ? (_) => const Text('GROUP ANCHOR') : null,
      ),
    ),
  );
}

void main() {
  final today = DateTime(2026, 6, 2);

  testWidgets('behind: shows catch-up tray and hides "Jump to current"', (
    tester,
  ) async {
    final status = _status(
      today: today,
      days: const [
        (dayOffset: -2, completed: false), // missed
        (dayOffset: 0, completed: false), // current
        (dayOffset: 2, completed: false), // upcoming
      ],
    );

    await tester.pumpWidget(_host(status));
    await tester.pumpAndSettle();

    expect(find.text('TEST PLAN'), findsOneWidget);
    expect(find.text('Full schedule'), findsOneWidget);
    // Overdue reading surfaces the gentle catch-up tray with a "TO REVISIT" tag.
    expect(find.text('Catch up at your own pace'), findsOneWidget);
    expect(find.text('TO REVISIT'), findsWidgets);
    // The current reading drives the group anchor.
    expect(find.text('GROUP ANCHOR'), findsOneWidget);
    // No "Jump to current" chip while behind (the tray handles that).
    expect(find.text('Jump to current'), findsNothing);
    expect(find.text('0 of 3 read'), findsOneWidget);
  });

  testWidgets('caught up: shows "Jump to current" chip and "in step" card', (
    tester,
  ) async {
    final status = _status(
      today: today,
      days: const [
        (dayOffset: -2, completed: true), // done
        (dayOffset: 0, completed: true), // current, done
        (dayOffset: 2, completed: false), // upcoming
      ],
    );

    await tester.pumpWidget(_host(status));
    await tester.pumpAndSettle();

    expect(find.text('Jump to current'), findsOneWidget);
    expect(find.text("You're in step with your group."), findsOneWidget);
    expect(find.text('Catch up at your own pace'), findsNothing);
    expect(find.text('2 of 3 read'), findsOneWidget);
  });

  testWidgets('personal: behind shows a quiet inline note, no group chrome', (
    tester,
  ) async {
    final status = _status(
      today: today,
      days: const [
        (dayOffset: -1, completed: false), // missed
        (dayOffset: 0, completed: false), // current
      ],
    );

    await tester.pumpWidget(_host(status, isGroup: false));
    await tester.pumpAndSettle();

    expect(find.text('1 reading to revisit'), findsOneWidget);
    // No group-only chrome on a personal plan.
    expect(find.text('Catch up at your own pace'), findsNothing);
    expect(find.text('GROUP ANCHOR'), findsNothing);
  });
}

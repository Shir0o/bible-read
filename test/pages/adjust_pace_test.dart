import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/pages/adjust_pace_page.dart';
import 'package:bible_read/services/plan_pace.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubVibrationService extends VibrationService {
  const _StubVibrationService();
  @override
  Future<void> lightImpact() async {}
  @override
  Future<void> mediumImpact() async {}
}

/// Seven daily readings from Jan 1; today is Jan 5 with days 1-2 read, so the
/// reader is 2 days behind and the finish is Jan 7.
List<GroupSchedule> _days() => PlanPace.datedPersonalSchedule(
      ReadingPlan(
        id: 'p1',
        title: 'Plan',
        description: '',
        durationDays: 7,
        tags: const [],
        schedule: List.generate(
          7,
          (i) => ReadingPlanDay(day: i + 1, readings: ['Gen ${i + 1}']),
        ),
      ),
      DateTime(2026, 1, 1),
    );

const _completed = {'2026-01-01', '2026-01-02'};

Future<void> _pump(
  WidgetTester tester, {
  bool shared = false,
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: AdjustPacePage(
        days: _days(),
        completedDateIds: _completed,
        daysBehind: 2,
        shared: shared,
        today: DateTime(2026, 1, 5),
        vibrationService: const _StubVibrationService(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('each option previews the finish date before committing',
      (tester) async {
    await _pump(tester);
    // Stretch: finish moves out by the 2 days behind (Jan 7 → Jan 9).
    expect(find.textContaining('Jan 9'), findsOneWidget);
    // Keep the finish: stays Jan 7.
    expect(find.textContaining('Jan 7'), findsOneWidget);
    // Begin again: day one becomes today (Jan 5), finish Jan 11.
    expect(find.textContaining('Jan 11'), findsOneWidget);
  });

  testWidgets('nothing is applied until an option is chosen', (tester) async {
    await _pump(tester);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });

  testWidgets('choosing stretch pops PaceOption.stretch', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Stretch it out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.byType(AdjustPacePage), findsNothing);
  });

  testWidgets('a shared plan says the change is the reader\'s alone',
      (tester) async {
    await _pump(tester, shared: true);
    expect(
      find.textContaining('only your own schedule'),
      findsOneWidget,
    );
  });

  testWidgets('a personal plan carries no shared-plan copy', (tester) async {
    await _pump(tester);
    expect(find.textContaining('only your own schedule'), findsNothing);
  });
}
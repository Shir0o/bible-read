import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/pages/adjust_pace_page.dart';
import 'package:bible_read/services/plan_pace.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/widgets/schedule_preview.dart';
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

AdjustPaceResult? _lastResult;

Future<void> _pump(
  WidgetTester tester, {
  bool shared = false,
}) async {
  _lastResult = null;
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                _lastResult =
                    await Navigator.of(context).push<AdjustPaceResult>(
                  MaterialPageRoute(
                    builder: (_) => AdjustPacePage(
                      days: _days(),
                      completedDateIds: _completed,
                      daysBehind: 2,
                      shared: shared,
                      today: DateTime(2026, 1, 5),
                      vibrationService: const _StubVibrationService(),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('each option previews the finish date before committing',
      (tester) async {
    await _pump(tester);
    // Stretch: finish moves out by the 2 days behind (Jan 7 → Jan 9).
    expect(
      find.textContaining('Finish moves 2 days later · ends Fri, Jan 9'),
      findsOneWidget,
    );
    // Keep the finish: stays Jan 7.
    expect(
      find.textContaining('Finish stays where it is · ends Wed, Jan 7'),
      findsOneWidget,
    );
    // Chapters per day: 5 unread chapters at 1 ch/day from Jan 5 -> Jan 9
    expect(
      find.textContaining('1 chapter a day · ends Fri, Jan 9'),
      findsOneWidget,
    );
    // Begin again: day one becomes today (Jan 5), finish Jan 11.
    expect(
      find.textContaining('Day one becomes today · ends Sun, Jan 11'),
      findsOneWidget,
    );
  });

  testWidgets('nothing is applied until an option is chosen', (tester) async {
    await _pump(tester);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Preview changes'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets(
      'choosing stretch and confirming dry run returns AdjustPaceResult',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Stretch it out'));
    await tester.pumpAndSettle();

    // Tap Preview changes
    await tester.tap(find.text('Preview changes'));
    await tester.pumpAndSettle();

    // Verify dry-run review screen
    expect(find.text('Review adjustment'), findsOneWidget);
    expect(find.text('2 completed readings kept'), findsOneWidget);
    expect(find.text('Timeline & pace comparison'), findsOneWidget);
    expect(find.byType(SchedulePreview), findsOneWidget);

    // Confirm & apply
    await tester.tap(find.text('Confirm & apply'));
    await tester.pumpAndSettle();

    expect(find.byType(AdjustPacePage), findsNothing);
    expect(_lastResult, isNotNull);
    expect(_lastResult!.option, PaceOption.stretch);
    expect(_lastResult!.chaptersPerDay, isNull);
  });

  testWidgets('dry-run Back button returns to option selection',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Stretch it out'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Preview changes'));
    await tester.pumpAndSettle();
    expect(find.text('Review adjustment'), findsOneWidget);

    // Tap Back
    await tester.tap(find.widgetWithText(OutlinedButton, 'Back'));
    await tester.pumpAndSettle();

    // Back on option selection
    expect(find.text('Adjust pace'), findsOneWidget);
    expect(find.text('Preview changes'), findsOneWidget);
  });

  testWidgets(
      'selecting Set chapters a day shows stepper and updates pace/finish',
      (tester) async {
    await _pump(tester);

    // Initially stepper is not visible
    expect(find.byKey(const Key('chapters_per_day_increment')), findsNothing);

    // Tap Set chapters a day
    await tester.tap(find.text('Set chapters a day'));
    await tester.pumpAndSettle();

    // Stepper is visible with initial 1 chapter / day (plan has 1 ch/day)
    expect(find.byKey(const Key('chapters_per_day_increment')), findsOneWidget);
    expect(find.text('1 chapter / day'), findsOneWidget);

    // Increment to 2 chapters / day
    await tester.tap(find.byKey(const Key('chapters_per_day_increment')));
    await tester.pumpAndSettle();

    expect(find.text('2 chapters / day'), findsOneWidget);

    // Preview changes
    await tester.tap(find.text('Preview changes'));
    await tester.pumpAndSettle();

    expect(find.text('Review adjustment'), findsOneWidget);
    expect(find.text('2 ch/day'), findsWidgets);

    // Confirm & apply
    await tester.tap(find.text('Confirm & apply'));
    await tester.pumpAndSettle();

    expect(_lastResult, isNotNull);
    expect(_lastResult!.option, PaceOption.chaptersPerDay);
    expect(_lastResult!.chaptersPerDay, 2);
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

import 'package:bible_read/models/exercise_challenge.dart';
import 'package:bible_read/services/exercise_tracker_service.dart';
import 'package:bible_read/widgets/exercise_status_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExerciseStatusSection', () {
    ExerciseChallenge buildChallenge({
      String id = 'c1',
      String name = 'Morning Run',
      String unit = 'minutes',
      double dailyGoal = 30,
      ExerciseTargetType targetType = ExerciseTargetType.atLeast,
      double? totalTarget = 600,
    }) {
      return ExerciseChallenge(
        id: id,
        uid: 'user-1',
        name: name,
        unit: unit,
        dailyGoal: dailyGoal,
        targetType: targetType,
        totalTarget: totalTarget,
      );
    }

    ExerciseChallengeSummary buildSummary({
      ExerciseChallenge? challenge,
      double todayTotal = 15,
      bool goalMetToday = false,
      int streak = 3,
      int graceAvailable = 1,
      int graceUsed = 1,
      double totalRecorded = 150,
      Map<String, double>? recentTotals,
    }) {
      final resolvedChallenge = challenge ?? buildChallenge();
      return ExerciseChallengeSummary(
        challenge: resolvedChallenge,
        todayTotal: todayTotal,
        goalMetToday: goalMetToday,
        currentStreak: streak,
        completedDays: 12,
        graceCreditsAvailable: graceAvailable,
        graceCreditsUsed: graceUsed,
        graceCreditsMonth: '2024-05',
        totalRecorded: totalRecorded,
        recentTotals: Map.unmodifiable(
          recentTotals ?? const {'2024-05-09': 15.0, '2024-05-08': 30.0},
        ),
      );
    }

    testWidgets('renders challenge summary with progress and quick actions',
        (tester) async {
      final challenge = buildChallenge();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseStatusSection(
              loading: false,
              summaries: [buildSummary(challenge: challenge)],
              onRecordAmount: (
                ExerciseChallenge c,
                double amount, {
                bool replace = false,
              }) async {},
              onOpenChallenges: () {},
            ),
          ),
        ),
      );

      expect(find.text('Daily Exercise'), findsOneWidget);
      expect(find.text('Morning Run'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.data?.contains('Goal: 30') == true,
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Logged today: 15'), findsOneWidget);
      expect(
          find.text('Streak: 3 days · 1 grace credits left'), findsOneWidget);
      expect(find.text('Manage challenges'), findsOneWidget);

      final progressFinder = find.byType(LinearProgressIndicator);
      expect(progressFinder, findsOneWidget);
      final progress = tester.widget<LinearProgressIndicator>(progressFinder);
      expect(progress.value, closeTo(0.5, 0.0001));

      expect(find.byIcon(Icons.add), findsWidgets);
    });

    testWidgets('disables logging actions when the goal is met',
        (tester) async {
      final challenge = buildChallenge();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseStatusSection(
              loading: false,
              summaries: [
                buildSummary(
                  challenge: challenge,
                  todayTotal: 30,
                  goalMetToday: true,
                ),
              ],
              onRecordAmount: (
                ExerciseChallenge c,
                double amount, {
                bool replace = false,
              }) async {},
            ),
          ),
        ),
      );

      expect(find.text('Goal complete for today!'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsNothing);

      final customButtonFinder = find.ancestor(
        of: find.text('Log custom total'),
        matching:
            find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
      );
      final customButton = tester.widget<ButtonStyleButton>(customButtonFinder);
      expect(customButton.onPressed, isNull);
    });

    testWidgets('shows validation errors when logging a custom amount',
        (tester) async {
      final challenge = buildChallenge(totalTarget: null);
      ExerciseChallenge? recordedChallenge;
      double? recordedAmount;
      bool? replaceFlag;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseStatusSection(
              loading: false,
              summaries: [buildSummary(challenge: challenge, todayTotal: 0)],
              onRecordAmount: (
                ExerciseChallenge c,
                double amount, {
                bool replace = false,
              }) async {
                recordedChallenge = c;
                recordedAmount = amount;
                replaceFlag = replace;
              },
            ),
          ),
        ),
      );

      await tester.tap(
        find.ancestor(
          of: find.byIcon(Icons.edit),
          matching:
              find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Enter a value (use 0 to clear)'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'abc');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Enter a valid number'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '-5');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Value must be positive'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '12.5');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(recordedChallenge, challenge);
      expect(recordedAmount, 12.5);
      expect(replaceFlag, isTrue);
    });
  });
}

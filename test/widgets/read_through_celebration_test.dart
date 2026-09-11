import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/read_through.dart';
import 'package:bible_read/theme/app_theme.dart';
import 'package:bible_read/widgets/read_through_celebration.dart';

import '../helpers/stub_vibration_service.dart';

void main() {
  ReadThrough row(
    ReadThroughScope scope, {
    int lap = 1,
    ReadThroughSource source = ReadThroughSource.detected,
  }) =>
      ReadThrough(
        id: '${scope.id}_$lap',
        scope: scope,
        completedAt: DateTime(2026, 9, 5),
        source: source,
        lapNumber: lap,
      );

  Future<void> show(
    WidgetTester tester, {
    required List<ReadThrough> completed,
    required ReadThroughCounts counts,
    VoidCallback? onDismiss,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.appTheme(AppTheme.designLightScheme),
        home: ReadThroughCelebration(
          completed: completed,
          counts: counts,
          vibrationService: StubVibrationService(),
          onDismiss: onDismiss ?? () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('names the testament and the lap', (tester) async {
    await show(
      tester,
      completed: [row(ReadThroughScope.newTestament, lap: 3)],
      counts: const ReadThroughCounts(oldTestament: 0, newTestament: 3),
    );

    expect(find.text('NEW TESTAMENT · LAP 3'), findsOneWidget);
    expect(find.textContaining('a third time'), findsOneWidget);
  });

  testWidgets('a testament alone says how far off a whole Bible is',
      (tester) async {
    await show(
      tester,
      completed: [row(ReadThroughScope.newTestament, lap: 2)],
      counts: const ReadThroughCounts(oldTestament: 1, newTestament: 2),
    );

    expect(
      find.textContaining('One more Old Testament'),
      findsOneWidget,
    );
  });

  group('the combined case', () {
    testWidgets('explains why the whole-Bible count moved', (tester) async {
      await show(
        tester,
        completed: [
          row(ReadThroughScope.newTestament, lap: 3),
          row(ReadThroughScope.wholeBible,
              lap: 2, source: ReadThroughSource.derived),
        ],
        counts: const ReadThroughCounts(oldTestament: 2, newTestament: 3),
      );

      // The trigger is still named...
      expect(find.text('NEW TESTAMENT · LAP 3'), findsOneWidget);
      // ...and so is the thing it completed, with the reason.
      expect(find.text('AND YOUR 2ND WHOLE BIBLE'), findsOneWidget);
      expect(find.text('The two testaments have paired off.'), findsOneWidget);
      expect(
        find.text('3 New Testaments, 2 Old — that makes 2 complete times '
            'through.'),
        findsOneWidget,
      );
    });

    testWidgets('reads correctly for a first whole Bible', (tester) async {
      await show(
        tester,
        completed: [
          row(ReadThroughScope.oldTestament),
          row(ReadThroughScope.wholeBible, source: ReadThroughSource.derived),
        ],
        counts: const ReadThroughCounts(oldTestament: 1, newTestament: 1),
      );

      expect(find.text('AND YOUR 1ST WHOLE BIBLE'), findsOneWidget);
      expect(
        find.text('1 New Testament, 1 Old — that makes one complete time '
            'through.'),
        findsOneWidget,
      );
    });

    testWidgets('shows one screen, not two', (tester) async {
      await show(
        tester,
        completed: [
          row(ReadThroughScope.newTestament, lap: 3),
          row(ReadThroughScope.wholeBible,
              lap: 2, source: ReadThroughSource.derived),
        ],
        counts: const ReadThroughCounts(oldTestament: 2, newTestament: 3),
      );

      expect(find.byType(ReadThroughCelebration), findsOneWidget);
      expect(find.text('Keep it'), findsOneWidget);
    });
  });

  testWidgets('dismisses', (tester) async {
    var dismissed = false;
    await show(
      tester,
      completed: [row(ReadThroughScope.newTestament)],
      counts: const ReadThroughCounts(oldTestament: 0, newTestament: 1),
      onDismiss: () => dismissed = true,
    );

    await tester.tap(find.text('Keep it'));
    await tester.pump();

    expect(dismissed, isTrue);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/streak_stats_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders streak and period statistics', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StreakStatsBox(
            currentStreak: 3,
            longestStreak: 10,
            totalReadDays: 40,
            periodCount: 5,
            periodLabel: 'This week',
            remainingGraceCredits: 2,
          ),
        ),
      ),
    );

    expect(find.text('Current streak: 3'), findsOneWidget);
    expect(find.text('Longest streak: 10'), findsOneWidget);
    expect(find.text('Total read days: 40'), findsOneWidget);
    expect(find.text('This week: 5'), findsOneWidget);
    expect(find.text('Grace credits remaining: 2'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/streak_stats_box.dart';

void main() {
  testWidgets('renders streak statistics', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StreakStatsBox(
            currentStreak: 5,
            longestStreak: 10,
            totalReadDays: 50,
            periodCount: 3,
            periodLabel: 'This week',
            remainingGraceCredits: 2,
          ),
        ),
      ),
    );

    expect(find.text('Current streak: 5'), findsOneWidget);
    expect(find.text('Longest streak: 10'), findsOneWidget);
    expect(find.text('Total read days: 50'), findsOneWidget);
    expect(find.text('This week: 3'), findsOneWidget);
    expect(find.text('Grace credits remaining: 2'), findsOneWidget);
  });

  testWidgets('renders optional description', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StreakStatsBox(
            currentStreak: 0,
            longestStreak: 0,
            totalReadDays: 0,
            periodCount: 0,
            periodLabel: '',
            description: Text('Test description'),
          ),
        ),
      ),
    );

    expect(find.text('Test description'), findsOneWidget);
  });
}

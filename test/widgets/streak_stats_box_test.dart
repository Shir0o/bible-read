import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/friend_streak_link.dart';
import 'package:bible_read/services/friendly_streak_service.dart';
import 'package:bible_read/widgets/streak_stats_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders streak and period statistics', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreakStatsBox(
            currentStreak: 3,
            longestStreak: 10,
            totalReadDays: 40,
            periodCount: 5,
            periodLabel: 'This week',
            remainingGraceCredits: 2,
            friendSummary: FriendlyStreakLinksSummary(
              activeLinks: [
                FriendStreakLink(
                  partnerUid: 'p1',
                  partnerName: 'Alice',
                  initiatedBy: 'user',
                  status: FriendStreakStatus.active,
                  currentStreak: 4,
                  lastUserCovered: null,
                  lastPartnerCovered: null,
                  createdAt: DateTime(2024),
                  updatedAt: DateTime(2024),
                  ownerUid: 'user',
                ),
              ],
              pendingLinks: const [],
            ),
            selectedPartnerId: 'p1',
          ),
        ),
      ),
    );

    expect(find.text('Current streak: 3'), findsOneWidget);
    expect(find.text('Longest streak: 10'), findsOneWidget);
    expect(find.text('Total read days: 40'), findsOneWidget);
    expect(find.text('This week: 5'), findsOneWidget);
    expect(find.text('Grace credits remaining: 2'), findsOneWidget);
    expect(find.text('Streak with Alice: 4 days'), findsOneWidget);
  });

  testWidgets('omits friend section when summary not provided', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreakStatsBox(
            currentStreak: 1,
            longestStreak: 2,
            totalReadDays: 3,
            periodCount: 4,
            periodLabel: 'Week reads',
          ),
        ),
      ),
    );

    expect(find.text('Current streak: 1'), findsOneWidget);
    expect(
      find.text('No streak partners yet. Invite a friend to share progress.'),
      findsNothing,
    );
  });
}

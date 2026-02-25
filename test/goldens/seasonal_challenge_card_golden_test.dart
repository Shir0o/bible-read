import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/seasonal_challenge_card.dart';
import 'package:bible_read/models/season.dart';
import 'package:bible_read/models/seasonal_challenge.dart';
import 'package:bible_read/models/seasonal_challenge_progress.dart';
import 'package:bible_read/models/seasonal_reward.dart';
import '../helpers/pump_golden.dart';

void main() {
  final now = DateTime(2023, 6, 15);

  final season = Season(
    id: 's1',
    title: 'Summer Challenge',
    description: 'Read every day!',
    startDate: DateTime(2023, 6, 1),
    endDate: DateTime(2023, 8, 31),
    bannerImageUrl: 'http://example.com/banner.png',
  );

  final reward = SeasonalReward(
    id: 'r1',
    type: 'badge',
    title: 'Summer Badge',
    description: 'A shiny badge',
    amount: 1,
    iconUrl: 'http://example.com/badge.png',
  );

  final challenge = SeasonalChallenge(
    id: 'c1',
    seasonId: 's1',
    title: 'Read 30 Chapters',
    description: 'Read 30 chapters this summer.',
    metric: 'chapters',
    goal: 30,
    reward: reward,
  );

  group('SeasonalChallengeCard Golden Test', () {
    testWidgets('SeasonalChallengeCard - In Progress', (tester) async {
      final progress = SeasonalChallengeProgress(
        id: 'p1',
        uid: 'u1',
        seasonId: 's1',
        challengeId: 'c1',
        totalProgress: 15, // 50%
      );

      await tester.pumpGolden(
        SeasonalChallengeCard(
          season: season,
          challenge: challenge,
          progress: progress,
          reward: reward,
          onClaim: () {},
          nowBuilder: () => now,
        ),
        brightness: Brightness.light,
      );

      await expectLater(
        find.byType(SeasonalChallengeCard),
        matchesGoldenFile('goldens/seasonal_challenge_card_in_progress.png'),
      );
    });

    testWidgets('SeasonalChallengeCard - Complete (Claimable)', (tester) async {
      final progress = SeasonalChallengeProgress(
        id: 'p1',
        uid: 'u1',
        seasonId: 's1',
        challengeId: 'c1',
        totalProgress: 30,
        completedAt: now,
      );

      await tester.pumpGolden(
        SeasonalChallengeCard(
          season: season,
          challenge: challenge,
          progress: progress,
          reward: reward,
          onClaim: () {},
          nowBuilder: () => now,
        ),
        brightness: Brightness.light,
      );

      await expectLater(
        find.byType(SeasonalChallengeCard),
        matchesGoldenFile('goldens/seasonal_challenge_card_complete.png'),
      );
    });

    testWidgets('SeasonalChallengeCard - Claimed', (tester) async {
      final progress = SeasonalChallengeProgress(
        id: 'p1',
        uid: 'u1',
        seasonId: 's1',
        challengeId: 'c1',
        totalProgress: 30,
        completedAt: now.subtract(const Duration(days: 1)),
        rewardClaimedAt: now,
      );

      await tester.pumpGolden(
        SeasonalChallengeCard(
          season: season,
          challenge: challenge,
          progress: progress,
          reward: reward,
          onClaim: () {},
          nowBuilder: () => now,
        ),
        brightness: Brightness.light,
      );

      await expectLater(
        find.byType(SeasonalChallengeCard),
        matchesGoldenFile('goldens/seasonal_challenge_card_claimed.png'),
      );
    });

    testWidgets('SeasonalChallengeCard - Dark Mode', (tester) async {
      final progress = SeasonalChallengeProgress(
        id: 'p1',
        uid: 'u1',
        seasonId: 's1',
        challengeId: 'c1',
        totalProgress: 10,
      );

      await tester.pumpGolden(
        SeasonalChallengeCard(
          season: season,
          challenge: challenge,
          progress: progress,
          reward: reward,
          onClaim: () {},
          nowBuilder: () => now,
        ),
        brightness: Brightness.dark,
      );

      await expectLater(
        find.byType(SeasonalChallengeCard),
        matchesGoldenFile('goldens/seasonal_challenge_card_dark.png'),
      );
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/season.dart';
import 'package:bible_read/models/seasonal_challenge.dart';
import 'package:bible_read/models/seasonal_challenge_progress.dart';
import 'package:bible_read/models/seasonal_reward.dart';
import 'package:bible_read/widgets/seasonal_challenge_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseSeason = Season(
    id: 's1',
    title: 'Spring Challenge',
    description: 'Grow your reading habits.',
    startDate: DateTime(2024, 3, 1),
    endDate: DateTime(2024, 5, 31),
  );

  final baseChallenge = SeasonalChallenge(
    id: 'c1',
    seasonId: 's1',
    title: 'Read Scripture',
    description: 'Finish the daily readings.',
    metric: 'chapters',
    goal: 20,
  );

  final baseReward = SeasonalReward(
    id: 'r1',
    type: 'points',
    title: 'Seasonal Badge',
    description: 'Awarded for completing the challenge.',
    amount: 50,
  );

  Widget buildCard({
    required SeasonalChallengeProgress progress,
    VoidCallback? onClaim,
    Season? season,
    SeasonalChallenge? challenge,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SeasonalChallengeCard(
          season: season ?? baseSeason,
          challenge: challenge ?? baseChallenge,
          progress: progress,
          reward: baseReward,
          onClaim: onClaim,
          remainingTimeBuilder: (_, __) => '3 days remaining',
          nowBuilder: () => DateTime(2024, 3, 10),
        ),
      ),
    );
  }

  testWidgets('renders progress indicator and label based on progress', (
    tester,
  ) async {
    final progress = SeasonalChallengeProgress(
      id: 's1_c1',
      uid: 'u1',
      seasonId: 's1',
      challengeId: 'c1',
      totalProgress: 5,
    );

    await tester.pumpWidget(buildCard(progress: progress));
    await tester.pump();

    expect(find.text('Read Scripture'), findsOneWidget);
    expect(find.text('5 / 20 chapters'), findsOneWidget);

    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, closeTo(0.25, 0.0001));
    expect(find.text('3 days remaining'), findsOneWidget);
  });

  testWidgets(
    'updates claim button state for in-progress, claimable, and claimed challenges',
    (tester) async {
      final incomplete = SeasonalChallengeProgress(
        id: 's1_c1',
        uid: 'u1',
        seasonId: 's1',
        challengeId: 'c1',
        totalProgress: 10,
      );

      await tester.pumpWidget(buildCard(progress: incomplete, onClaim: () {}));
      await tester.pump();

      var button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
      expect(find.text('In progress'), findsOneWidget);

      final complete = SeasonalChallengeProgress(
        id: 's1_c1',
        uid: 'u1',
        seasonId: 's1',
        challengeId: 'c1',
        totalProgress: 20,
      );

      await tester.pumpWidget(buildCard(progress: complete, onClaim: () {}));
      await tester.pump();

      button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);
      expect(find.text('Claim reward'), findsOneWidget);

      final claimed = SeasonalChallengeProgress(
        id: 's1_c1',
        uid: 'u1',
        seasonId: 's1',
        challengeId: 'c1',
        totalProgress: 20,
        rewardClaimedAt: DateTime(2024, 3, 9),
      );

      await tester.pumpWidget(buildCard(progress: claimed, onClaim: () {}));
      await tester.pump();

      button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
      expect(find.text('Claimed'), findsOneWidget);
    },
  );

  testWidgets('invokes onClaim callback when claim button tapped', (
    tester,
  ) async {
    var callCount = 0;
    final progress = SeasonalChallengeProgress(
      id: 's1_c1',
      uid: 'u1',
      seasonId: 's1',
      challengeId: 'c1',
      totalProgress: 25,
    );

    await tester.pumpWidget(
      buildCard(
        progress: progress,
        onClaim: () {
          callCount++;
        },
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Claim reward'));
    await tester.pump();

    expect(callCount, 1);
  });
}

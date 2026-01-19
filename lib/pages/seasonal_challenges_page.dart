import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/season.dart';
import '../models/seasonal_challenge.dart';
import '../services/seasonal_challenge_service.dart';
import '../widgets/common_styles.dart';
import '../models/seasonal_challenge_progress.dart';
import '../widgets/seasonal_challenge_card.dart';

class SeasonalChallengesView extends StatelessWidget {
  final FirebaseAuth auth;
  final SeasonalChallengeService service;

  const SeasonalChallengesView({
    super.key,
    required this.auth,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) return const Center(child: Text('Please sign in'));

    return FutureBuilder<Season?>(
      future: service.fetchActiveSeason(),
      builder: (context, seasonSnapshot) {
        if (seasonSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final season = seasonSnapshot.data;
        if (season == null) {
          return const Center(child: Text('No active season currently.'));
        }

        return StreamBuilder<List<SeasonalChallenge>>(
          stream: service.streamChallenges(season.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                  child: Text('Failed to load seasonal challenges.'));
            }
            final challenges = snapshot.data ?? [];
            if (challenges.isEmpty) {
              return const Center(child: Text('No active challenges at the moment.'));
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: challenges.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      season.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  );
                }
                final challenge = challenges[index - 1];
                return _SeasonalChallengeItem(
                  auth: auth,
                  service: service,
                  season: season,
                  challenge: challenge,
                );
              },
            );
          },
        );
      },
    );
  }
}

// Wrapper
class SeasonalChallengesPage extends StatelessWidget {
  final FirebaseAuth auth;
  final SeasonalChallengeService service;

  const SeasonalChallengesPage({
    super.key,
    required this.auth,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar(context, 'Seasonal Challenges'),
      body: SeasonalChallengesView(auth: auth, service: service),
    );
  }
}

class _SeasonalChallengeItem extends StatelessWidget {
  final FirebaseAuth auth;
  final SeasonalChallengeService service;
  final Season season;
  final SeasonalChallenge challenge;

  const _SeasonalChallengeItem({
    required this.auth,
    required this.service,
    required this.season,
    required this.challenge,
  });

  @override
  Widget build(BuildContext context) {
    if (challenge.reward == null) return const SizedBox.shrink();

    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<SeasonalChallengeProgress?>(
      stream: service.streamProgress(
        uid: user.uid,
        seasonId: season.id,
        challengeId: challenge.id,
      ),
      builder: (context, snapshot) {
        final progress = snapshot.data ??
            SeasonalChallengeProgress(
              id: '',
              uid: user.uid,
              seasonId: season.id,
              challengeId: challenge.id,
            );
        return SeasonalChallengeCard(
          season: season,
          challenge: challenge,
          progress: progress,
          reward: challenge.reward!,
          onClaim: () async {
            try {
              await service.claimReward(uid: user.uid, progress: progress);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reward claimed!')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to claim reward: $e')),
                );
              }
            }
          },
        );
      },
    );
  }
}

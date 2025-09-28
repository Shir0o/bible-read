import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/season.dart';
import '../models/seasonal_challenge.dart';
import '../models/seasonal_challenge_progress.dart';
import '../models/seasonal_reward.dart';
import '../services/error_logger.dart';
import '../services/seasonal_challenge_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/menu_button.dart';
import '../widgets/seasonal_challenge_card.dart';

class SeasonalChallengesPage extends StatefulWidget {
  SeasonalChallengesPage({
    super.key,
    FirebaseAuth? auth,
    SeasonalChallengeService? service,
  })  : auth = auth ?? FirebaseAuth.instance,
        service = service ?? SeasonalChallengeService();

  final FirebaseAuth auth;
  final SeasonalChallengeService service;

  @override
  State<SeasonalChallengesPage> createState() => _SeasonalChallengesPageState();
}

class _SeasonalChallengesPageState extends State<SeasonalChallengesPage> {
  late final Stream<Season?> _seasonStream;

  @override
  void initState() {
    super.initState();
    _seasonStream = widget.service.firestore
        .collection(SeasonalChallengePaths.seasons)
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      Season? activeSeason;
      for (final doc in snapshot.docs) {
        final season = Season.fromFirestore(doc);
        if (season.isActive(now)) {
          if (activeSeason == null ||
              season.startDate.isAfter(activeSeason.startDate)) {
            activeSeason = season;
          }
        }
      }
      return activeSeason;
    }).handleError((Object error, StackTrace stackTrace) {
      ErrorLogger.log(error, stackTrace);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        'Seasonal Challenges',
        leading: const MenuButton(),
        automaticallyImplyLeading: false,
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: user == null
            ? const Center(
                child: Text('Please sign in to view seasonal challenges.'),
              )
            : StreamBuilder<Season?>(
                stream: _seasonStream,
                builder: (context, seasonSnapshot) {
                  if (seasonSnapshot.hasError) {
                    return const Center(
                      child: Text('Failed to load seasonal challenges.'),
                    );
                  }

                  if (seasonSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final season = seasonSnapshot.data;
                  if (season == null) {
                    return const Center(
                      child: Text(
                        'No seasonal challenges are active right now.\nCheck back soon!',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  return StreamBuilder<List<SeasonalChallenge>>(
                    stream: widget.service.streamChallenges(season.id),
                    builder: (context, challengeSnapshot) {
                      if (challengeSnapshot.hasError) {
                        return const Center(
                          child: Text('Failed to load seasonal challenges.'),
                        );
                      }

                      if (!challengeSnapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final challenges = challengeSnapshot.data!;
                      if (challenges.isEmpty) {
                        return RefreshIndicator(
                          onRefresh: _refreshSeason,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            children: [
                              _buildSeasonHeader(context, season),
                              const SizedBox(height: 24),
                              const Text(
                                'No challenges are available for this season yet.\nPlease check again later.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: _refreshSeason,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: challenges.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return _buildSeasonHeader(context, season);
                            }

                            final challenge = challenges[index - 1];
                            return Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: _ChallengeProgressCard(
                                season: season,
                                challenge: challenge,
                                service: widget.service,
                                userId: user.uid,
                                onClaimed: _onRewardClaimed,
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }

  Widget _buildSeasonHeader(BuildContext context, Season season) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final start = localizations.formatMediumDate(season.startDate);
    final end = localizations.formatMediumDate(season.endDate);
    final rangeLabel = '$start - $end';
    final titleStyle = theme.textTheme.headlineSmall;
    final bodyStyle = theme.textTheme.bodyMedium;
    final subtleStyle = theme.textTheme.bodySmall;

    return CommonStyles.buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(season.title, style: titleStyle),
          const SizedBox(height: 8),
          if (season.description.isNotEmpty) ...[
            Text(season.description, style: bodyStyle),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.calendar_month, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  rangeLabel,
                  style: subtleStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _refreshSeason() async {
    try {
      await widget.service.fetchActiveSeason();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seasonal challenges refreshed.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to refresh challenges. Please try again.'),
        ),
      );
    }
  }

  Future<void> _onRewardClaimed() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reward claimed!')),
    );
  }
}

class _ChallengeProgressCard extends StatelessWidget {
  const _ChallengeProgressCard({
    required this.season,
    required this.challenge,
    required this.service,
    required this.userId,
    required this.onClaimed,
  });

  final Season season;
  final SeasonalChallenge challenge;
  final SeasonalChallengeService service;
  final String userId;
  final Future<void> Function() onClaimed;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SeasonalChallengeProgress?>(
      stream: service.streamProgress(
        uid: userId,
        seasonId: season.id,
        challengeId: challenge.id,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SizedBox.shrink();
        }

        final progress = snapshot.data ??
            SeasonalChallengeProgress(
              id: '${season.id}_${challenge.id}',
              uid: userId,
              seasonId: season.id,
              challengeId: challenge.id,
            );
        final reward = challenge.reward ??
            const SeasonalReward(
              id: 'reward',
              type: '',
              title: 'Reward',
              description: '',
              amount: 0,
            );

        return SeasonalChallengeCard(
          season: season,
          challenge: challenge,
          progress: progress,
          reward: reward,
          onTap: () {},
          onClaim: () => _claimReward(context, progress),
        );
      },
    );
  }

  Future<void> _claimReward(
    BuildContext context,
    SeasonalChallengeProgress progress,
  ) async {
    try {
      await service.claimReward(uid: userId, progress: progress);
      await onClaimed();
    } catch (error, stackTrace) {
      await ErrorLogger.log(error, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to claim reward. Please try again.'),
          ),
        );
      }
    }
  }
}

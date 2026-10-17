import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/season.dart';
import '../../pages/challenges_page.dart';
import '../../services/seasonal_challenge_service.dart';
import '../../services/vibration_service.dart';
import '../../theme/app_theme.dart';

/// The active Seasonal Challenge as a gold card in the Plans list. With no
/// season active it is a quiet row, so Challenges stays reachable.
class PathChallengeCard extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final VibrationService vibrationService;
  final DateTime Function() dateProvider;

  const PathChallengeCard({
    super.key,
    required this.firestore,
    required this.auth,
    required this.vibrationService,
    required this.dateProvider,
  });

  @override
  State<PathChallengeCard> createState() => _PathChallengeCardState();
}

class _PathChallengeCardState extends State<PathChallengeCard> {
  late final Future<Season?> _season;

  @override
  void initState() {
    super.initState();
    _season = SeasonalChallengeService(
      firestore: widget.firestore,
      clock: widget.dateProvider,
    ).fetchActiveSeason().catchError((Object _) => null);
  }

  String _daysLeft(Season season) {
    final today = widget.dateProvider();
    final left = DateTime(
      season.endDate.year,
      season.endDate.month,
      season.endDate.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (left <= 0) return 'Ends today';
    return '$left ${left == 1 ? 'day' : 'days'} left';
  }

  void _openChallenges() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChallengesPage(
          auth: widget.auth,
          firestore: widget.firestore,
          vibrationService: widget.vibrationService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return FutureBuilder<Season?>(
      future: _season,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final season = snapshot.data;
        if (season == null) return _NoSeasonRow(onTap: _openChallenges);
        final onGold = colorScheme.onTertiaryContainer;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.hPadding,
            AppSpacing.gap8,
            AppSpacing.hPadding,
            0,
          ),
          child: Material(
            color: colorScheme.tertiaryContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.rCard),
              side: BorderSide(
                color: colorScheme.tertiary.withValues(alpha: 0.28),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _openChallenges,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SEASONAL CHALLENGE',
                            style: textTheme.labelSmall?.copyWith(
                              color: onGold,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.gap4),
                          Text(
                            season.title,
                            style: textTheme.titleLarge?.copyWith(
                              color: onGold,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.gap2),
                          Text(
                            _daysLeft(season),
                            style: textTheme.bodySmall?.copyWith(
                              color: onGold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: onGold),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NoSeasonRow extends StatelessWidget {
  const _NoSeasonRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.hPadding,
        AppSpacing.gap8,
        AppSpacing.hPadding,
        0,
      ),
      child: Material(
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.rCard),
          side: BorderSide(color: AppColors.of(context).border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('path-challenges-link'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.cardPadding,
              vertical: AppSpacing.gap12,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.emoji_events_outlined,
                  size: 22,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.gap12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Seasonal challenges', style: textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.gap2),
                      Text(
                        'None running right now',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

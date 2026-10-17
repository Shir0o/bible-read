import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/season.dart';
import '../../pages/challenges_page.dart';
import '../../services/seasonal_challenge_service.dart';
import '../../services/vibration_service.dart';
import '../../theme/app_theme.dart';

/// The active Seasonal Challenge as a gold card in the Plans list. Renders
/// nothing when no season is active.
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return FutureBuilder<Season?>(
      future: _season,
      builder: (context, snapshot) {
        final season = snapshot.data;
        if (season == null) return const SizedBox.shrink();
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
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChallengesPage(
                    auth: widget.auth,
                    firestore: widget.firestore,
                    vibrationService: widget.vibrationService,
                  ),
                ),
              ),
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

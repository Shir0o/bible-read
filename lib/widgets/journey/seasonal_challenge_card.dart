import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/season.dart';
import '../../pages/challenges_page.dart';
import '../../services/seasonal_challenge_service.dart';
import '../../services/vibration_service.dart';
import '../../theme/app_theme.dart';

/// The active Seasonal Challenge as a slim gold card on Today, beneath the
/// reading section. Renders nothing while loading or with no season active.
class TodayChallengeCard extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final VibrationService vibrationService;
  final DateTime Function() dateProvider;

  const TodayChallengeCard({
    super.key,
    required this.firestore,
    required this.auth,
    required this.vibrationService,
    required this.dateProvider,
  });

  @override
  State<TodayChallengeCard> createState() => _TodayChallengeCardState();
}

class _TodayChallengeCardState extends State<TodayChallengeCard> {
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
        final season = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done ||
            season == null) {
          return const SizedBox.shrink();
        }
        final onGold = colorScheme.onTertiaryContainer;
        final border = colorScheme.tertiary.withValues(alpha: 0.28);
        final daysLeft = _daysLeft(season);
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.gap12),
          child: Semantics(
            button: true,
            label: 'Seasonal challenge: ${season.title}, $daysLeft',
            excludeSemantics: true,
            child: Material(
              color: colorScheme.tertiaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.rButton),
                side: BorderSide(color: border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const Key('today-challenge-card'),
                onTap: _openChallenges,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLowest,
                            shape: BoxShape.circle,
                            border: Border.all(color: border),
                          ),
                          child: Icon(
                            Icons.emoji_events_outlined,
                            size: 18,
                            color: colorScheme.tertiary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.gap12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                season.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleSmall?.copyWith(
                                  color: onGold,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.gap2),
                              Text(
                                'Seasonal challenge · $daysLeft',
                                style: textTheme.bodySmall?.copyWith(
                                  color: onGold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.gap8),
                        Icon(Icons.chevron_right_rounded, color: onGold),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

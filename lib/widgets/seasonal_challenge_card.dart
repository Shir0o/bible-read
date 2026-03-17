import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/season.dart';
import '../models/seasonal_challenge.dart';
import '../models/seasonal_challenge_progress.dart';
import '../models/seasonal_reward.dart';
import 'common_styles.dart';

/// Card widget that displays the user's status for a seasonal challenge.
///
/// Provide localized strings by customizing the optional label parameters or by
/// supplying [remainingTimeBuilder]. By default, simple English labels are
/// used.
class SeasonalChallengeCard extends StatelessWidget {
  /// The active season containing the challenge.
  final Season season;

  /// Challenge definition displayed by the card.
  final SeasonalChallenge challenge;

  /// The user's progress for the challenge.
  final SeasonalChallengeProgress progress;

  /// Reward granted after claiming the challenge.
  final SeasonalReward reward;

  /// Callback triggered when the user taps the claim button.
  final VoidCallback? onClaim;

  /// Optional onTap to make the entire card tappable with an ink overlay.
  /// If null, the card is non-tappable and uses a regular Card.
  final VoidCallback? onTap;

  /// Optional custom margin for the surrounding card.
  final EdgeInsetsGeometry? margin;

  /// Optional custom label for the claim action button.
  final String? claimButtonLabel;

  /// Optional custom label shown when the reward has already been claimed.
  final String? claimedButtonLabel;

  /// Optional custom label shown while the challenge is still in progress.
  final String? inProgressButtonLabel;

  /// Optional label displayed after the season has ended.
  final String? seasonEndedLabel;

  /// Custom builder for the remaining time label. Receives the build context
  /// and the duration until the season ends.
  final String Function(BuildContext context, Duration remaining)?
      remainingTimeBuilder;

  /// Optional override for the current time, enabling deterministic tests.
  final DateTime Function()? nowBuilder;

  /// Creates a [SeasonalChallengeCard].
  const SeasonalChallengeCard({
    super.key,
    required this.season,
    required this.challenge,
    required this.progress,
    required this.reward,
    this.onClaim,
    this.onTap,
    this.margin,
    this.claimButtonLabel,
    this.claimedButtonLabel,
    this.inProgressButtonLabel,
    this.seasonEndedLabel,
    this.remainingTimeBuilder,
    this.nowBuilder,
  });

  bool get _isClaimed => progress.rewardClaimedAt != null;

  bool get _isComplete =>
      progress.completedAt != null || progress.totalProgress >= challenge.goal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final materialLocalizations = MaterialLocalizations.of(context);
    final titleStyle =
        theme.textTheme.titleMedium?.merge(AppTextStyles.subtitle(context)) ??
            AppTextStyles.subtitle(context);
    final bodyStyle =
        theme.textTheme.bodyMedium?.merge(AppTextStyles.body(context)) ??
            AppTextStyles.body(context);
    final subtleStyle =
        theme.textTheme.bodySmall?.merge(AppTextStyles.body(context)) ??
            AppTextStyles.body(context);

    final now = nowBuilder?.call() ?? DateTime.now();
    final ended = now.isAfter(season.endDate);
    final remaining = ended ? Duration.zero : season.endDate.difference(now);
    final remainingText = ended
        ? (seasonEndedLabel ?? 'Season ended')
        : remainingTimeBuilder?.call(context, remaining) ??
            _defaultRemainingTime(materialLocalizations, remaining);

    final goal = challenge.goal <= 0 ? 1 : challenge.goal;
    final clampedProgress = math.max(0, progress.totalProgress);
    final completion =
        challenge.goal <= 0 ? 1.0 : (clampedProgress / goal).clamp(0.0, 1.0);
    final progressText =
        '${materialLocalizations.formatDecimal(clampedProgress)} / '
                '${materialLocalizations.formatDecimal(challenge.goal)} '
                '${challenge.metric}'
            .trim();

    final canClaim = onClaim != null && _isComplete && !_isClaimed;
    final buttonLabel = _resolveButtonLabel(materialLocalizations);

    final buildCard = onTap == null
        ? ({required Widget child, EdgeInsetsGeometry? margin}) =>
            CommonStyles.buildCard(
              context: context,
              margin: margin,
              child: child,
            )
        : ({required Widget child, EdgeInsetsGeometry? margin}) =>
            CommonStyles.buildTappableCard(
              context: context,
              onTap: onTap,
              margin: margin,
              child: child,
            );

    return buildCard(
      margin: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(challenge.title, style: titleStyle),
          const SizedBox(height: 8),
          Text(challenge.description, style: bodyStyle),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: completion,
            minHeight: 8,
          ),
          const SizedBox(height: 8),
          Text(progressText, style: subtleStyle),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.schedule, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  remainingText,
                  style: subtleStyle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.card_giftcard, color: theme.colorScheme.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reward.title,
                        style: bodyStyle.copyWith(fontWeight: FontWeight.w600)),
                    if (reward.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(reward.description, style: subtleStyle),
                    ],
                    if (_rewardAmountText(materialLocalizations)
                        .isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _rewardAmountText(materialLocalizations),
                        style: subtleStyle,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: canClaim ? onClaim : null,
              child: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }

  String _rewardAmountText(MaterialLocalizations localizations) {
    if (reward.amount <= 0 && reward.type.isEmpty) {
      return '';
    }
    final formattedAmount =
        reward.amount > 0 ? localizations.formatDecimal(reward.amount) : '';
    if (formattedAmount.isEmpty) {
      return reward.type;
    }
    if (reward.type.isEmpty) {
      return formattedAmount;
    }
    return '$formattedAmount ${reward.type}';
  }

  String _resolveButtonLabel(MaterialLocalizations localizations) {
    if (_isClaimed) {
      return claimedButtonLabel ?? 'Claimed';
    }
    if (!_isComplete) {
      return inProgressButtonLabel ?? 'In progress';
    }
    return claimButtonLabel ?? 'Claim reward';
  }

  String _defaultRemainingTime(
    MaterialLocalizations localizations,
    Duration remaining,
  ) {
    final totalMinutes = math.max(remaining.inMinutes, 0);
    final totalHours = remaining.inHours;
    final days = remaining.inDays;
    if (days > 0) {
      final hours = totalHours - days * 24;
      final daysLabel = '${localizations.formatDecimal(days)}d';
      if (hours > 0) {
        final hoursLabel = '${localizations.formatDecimal(hours)}h';
        return '$daysLabel $hoursLabel remaining';
      }
      return '$daysLabel remaining';
    }
    if (totalHours > 0) {
      return '${localizations.formatDecimal(totalHours)}h remaining';
    }
    final minutes = math.max(totalMinutes, 1);
    return '${localizations.formatDecimal(minutes)}m remaining';
  }
}

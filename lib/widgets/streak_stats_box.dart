import 'package:flutter/material.dart';

import 'common_styles.dart';

/// Displays streak statistics in a card.
class StreakStatsBox extends StatelessWidget {
  /// Current streak length in days.
  final int currentStreak;

  /// Longest streak length in days.
  final int longestStreak;

  /// Total number of days the user has read.
  final int totalReadDays;

  /// Count of read days within the selected period.
  final int periodCount;

  /// Label for the selected period, e.g. "This week".
  final String periodLabel;

  /// Remaining grace credits available for the current month, if known.
  final int? remainingGraceCredits;

  /// Optional description explaining how streak tracking works.
  final Widget? description;

  const StreakStatsBox({
    super.key,
    required this.currentStreak,
    required this.longestStreak,
    required this.totalReadDays,
    required this.periodCount,
    required this.periodLabel,
    this.remainingGraceCredits,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    return CommonStyles.buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current streak: $currentStreak', style: AppTextStyles.body),
          Text('Longest streak: $longestStreak', style: AppTextStyles.body),
          Text('Total read days: $totalReadDays', style: AppTextStyles.body),
          Text('$periodLabel: $periodCount', style: AppTextStyles.body),
          if (remainingGraceCredits != null)
            Text(
              'Grace credits remaining: $remainingGraceCredits',
              style: AppTextStyles.body,
            ),
          if (description != null) ...[
            const SizedBox(height: 8),
            description!,
          ],
        ],
      ),
    );
  }
}

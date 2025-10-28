
import 'dart:async';

import 'package:flutter/material.dart';

import '../models/exercise_challenge.dart';
import '../services/exercise_tracker_service.dart';
import 'common_styles.dart';
import 'section_header.dart';

/// Signature for recording an exercise amount for a challenge.
typedef ExerciseAmountRecorder = Future<void> Function(
  ExerciseChallenge challenge,
  double amount, {
  bool replace,
});

/// Displays the user's active exercise challenge summaries with logging controls.
class ExerciseStatusSection extends StatelessWidget {
  const ExerciseStatusSection({
    super.key,
    required this.loading,
    required this.summaries,
    this.error,
    this.onRecordAmount,
    this.onOpenChallenges,
    this.onCreateChallenge,
    this.onRetry,
  });

  /// Whether challenge summaries are currently loading.
  final bool loading;

  /// Loaded challenge summaries.
  final List<ExerciseChallengeSummary> summaries;

  /// Optional error message when summaries fail to load.
  final String? error;

  /// Handler invoked when the user records a new amount.
  final ExerciseAmountRecorder? onRecordAmount;

  /// Invoked when the "Manage challenges" button is tapped.
  final VoidCallback? onOpenChallenges;

  /// Invoked when creating the first challenge from the empty state.
  final VoidCallback? onCreateChallenge;

  /// Invoked when the user retries after an error.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Daily Exercise'),
        if (loading) _buildLoadingCard() else _buildContent(context),
      ],
    );
  }

  Widget _buildLoadingCard() {
    return CommonStyles.buildCard(
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text('Loading exercise challenges...'),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (error != null) {
      return CommonStyles.buildCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (onRetry != null)
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
                if (onOpenChallenges != null) ...[
                  if (onRetry != null) const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: onOpenChallenges,
                    child: const Text('Open challenges'),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }

    if (summaries.isEmpty) {
      return CommonStyles.buildCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No exercise challenges yet.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create a challenge to start tracking daily goals alongside your reading streak.',
            ),
            const SizedBox(height: 16),
            if (onCreateChallenge != null)
              FilledButton.icon(
                onPressed: onCreateChallenge,
                icon: const Icon(Icons.add),
                label: const Text('Create a challenge'),
              ),
          ],
        ),
      );
    }

    final children = <Widget>[
      for (final summary in summaries)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _ExerciseChallengeCard(
            summary: summary,
            onRecordAmount: onRecordAmount,
          ),
        ),
      if (onOpenChallenges != null)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onOpenChallenges,
            icon: const Icon(Icons.manage_search),
            label: const Text('Manage challenges'),
          ),
        ),
    ];

    return Column(children: children);
  }
}

class _ExerciseChallengeCard extends StatelessWidget {
  const _ExerciseChallengeCard({
    required this.summary,
    required this.onRecordAmount,
  });

  final ExerciseChallengeSummary summary;
  final ExerciseAmountRecorder? onRecordAmount;

  ExerciseChallenge get challenge => summary.challenge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goalLabel = _goalLabel();
    final remainingLabel = _remainingLabel();
    final goalMet = summary.goalMetToday;
    final progress = _progressValue();
    final quickAdds = _quickAddOptions();
    final totalTarget = challenge.totalTarget;
    final totalRemaining =
        totalTarget != null ? (totalTarget - summary.totalRecorded) : null;

    return CommonStyles.buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      challenge.name,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (goalLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(goalLabel, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              Chip(
                avatar: Icon(
                  goalMet ? Icons.check_circle : Icons.flag_outlined,
                  color: goalMet
                      ? theme.colorScheme.onSecondaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
                label: Text(goalMet ? 'Goal met' : 'Keep going'),
                backgroundColor: goalMet
                    ? theme.colorScheme.secondaryContainer
                    : theme.colorScheme.surfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Logged today: ${_formatAmount(summary.todayTotal)} ${challenge.unit}',
            style: theme.textTheme.bodyMedium,
          ),
          if (remainingLabel != null) ...[
            const SizedBox(height: 6),
            Text(remainingLabel, style: theme.textTheme.bodySmall),
          ],
          if (progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
          ],
          if (totalTarget != null) ...[
            const SizedBox(height: 12),
            Text(
              'Total progress: ${_formatAmount(summary.totalRecorded)} / '
              '${_formatAmount(totalTarget)} ${challenge.unit}',
              style: theme.textTheme.bodyMedium,
            ),
            if (totalRemaining != null)
              Text(
                totalRemaining <= 0
                    ? 'Lifetime goal reached!'
                    : 'Remaining overall: ${_formatAmount(totalRemaining)} '
                        '${challenge.unit}',
                style: theme.textTheme.bodySmall,
              ),
          ]
          else ...[
            const SizedBox(height: 12),
            Text(
              'Lifetime total: ${_formatAmount(summary.totalRecorded)} '
              '${challenge.unit}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Streak: ${summary.currentStreak} days · '
            '${summary.graceCreditsAvailable} grace credits left',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (onRecordAmount != null && quickAdds.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final amount in quickAdds)
                  FilledButton.tonalIcon(
                    onPressed: () => unawaited(
                      onRecordAmount!(
                        challenge,
                        amount,
                        replace: false,
                      ),
                    ),
                    icon: const Icon(Icons.add),
                    label: Text(
                      '+${_formatAmount(amount)}'
                      '${challenge.unit.isNotEmpty ? ' ${challenge.unit}' : ''}',
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _showCustomAmountDialog(context),
                  icon: const Icon(Icons.edit),
                  label: const Text('Log custom total'),
                ),
              ],
            )
          else if (onRecordAmount != null)
            OutlinedButton.icon(
              onPressed: () => _showCustomAmountDialog(context),
              icon: const Icon(Icons.edit),
              label: const Text('Log custom total'),
            ),
          const SizedBox(height: 16),
          _buildHistory(context),
        ],
      ),
    );
  }

  double? _progressValue() {
    if (challenge.dailyGoal <= 0) {
      return null;
    }
    if (challenge.targetType != ExerciseTargetType.atLeast) {
      return null;
    }
    return summary.todayTotal / challenge.dailyGoal;
  }

  String? _goalLabel() {
    if (challenge.dailyGoal <= 0) {
      return null;
    }
    final goalAmount = _formatAmount(challenge.dailyGoal);
    final unitLabel = challenge.unit.isEmpty ? '' : ' ${challenge.unit}';
    switch (challenge.targetType) {
      case ExerciseTargetType.atLeast:
        return 'Goal: $goalAmount$unitLabel or more each day';
      case ExerciseTargetType.atMost:
        return 'Goal: stay below $goalAmount$unitLabel per day';
      case ExerciseTargetType.exactly:
        return 'Goal: exactly $goalAmount$unitLabel per day';
    }
  }

  String? _remainingLabel() {
    final unitLabel = challenge.unit.isEmpty ? '' : ' ${challenge.unit}';
    switch (challenge.targetType) {
      case ExerciseTargetType.atLeast:
        if (challenge.dailyGoal <= 0) {
          return null;
        }
        final remaining = challenge.dailyGoal - summary.todayTotal;
        if (remaining <= 0) {
          return 'Goal complete for today!';
        }
        return 'Need ${_formatAmount(remaining)}$unitLabel more to hit today\'s goal.';
      case ExerciseTargetType.atMost:
        if (challenge.dailyGoal <= 0) {
          return null;
        }
        final remaining = challenge.dailyGoal - summary.todayTotal;
        if (remaining >= 0) {
          return '${_formatAmount(remaining)}$unitLabel remaining before hitting the limit.';
        }
        return 'Over the limit by ${_formatAmount(remaining.abs())}$unitLabel.';
      case ExerciseTargetType.exactly:
        if (challenge.dailyGoal <= 0) {
          return null;
        }
        final delta = summary.todayTotal - challenge.dailyGoal;
        if (delta.abs() < 0.01) {
          return 'Perfect! You hit today\'s exact target.';
        }
        if (delta < 0) {
          return '${_formatAmount(delta.abs())}$unitLabel left to reach the exact goal.';
        }
        return 'Over by ${_formatAmount(delta)}$unitLabel for today\'s exact goal.';
    }
  }

  List<double> _quickAddOptions() {
    final List<double> options = [];
    void add(double value) {
      final normalized = double.parse(value.toStringAsFixed(2));
      if (normalized <= 0) {
        return;
      }
      final exists = options.any((element) =>
          (element - normalized).abs() < 0.001);
      if (!exists) {
        options.add(normalized);
      }
    }

    final goal = challenge.dailyGoal;
    if (goal > 0) {
      add(goal);
      add(goal / 2);
    }
    add(1);
    add(5);
    return options.take(3).toList();
  }

  Future<void> _showCustomAmountDialog(BuildContext context) async {
    if (onRecordAmount == null) {
      return;
    }
    final controller = TextEditingController(
      text: summary.todayTotal > 0
          ? _formatAmount(summary.todayTotal)
          : '',
    );
    final formKey = GlobalKey<FormState>();

    final double? result = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Log ${challenge.name} total'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Total for today'
                    '${challenge.unit.isNotEmpty ? ' (${challenge.unit})' : ''}',
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) {
                  return 'Enter a value (use 0 to clear)';
                }
                final parsed = double.tryParse(text);
                if (parsed == null) {
                  return 'Enter a valid number';
                }
                if (parsed < 0) {
                  return 'Value must be positive';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) {
                  return;
                }
                final text = controller.text.trim();
                final parsed = double.tryParse(text) ?? 0;
                Navigator.of(dialogContext).pop(parsed);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (result != null) {
      await onRecordAmount!(challenge, result, replace: true);
    }
  }

  Widget _buildHistory(BuildContext context) {
    final entries = summary.recentTotals.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    final displayEntries = entries.take(7).toList();
    final localizations = MaterialLocalizations.of(context);

    if (displayEntries.isEmpty) {
      return Text(
        'No recent activity logged.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent history',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Column(
          children: displayEntries.map((entry) {
            final date = DateTime.tryParse(entry.key);
            final amount = entry.value;
            final formattedDate = date != null
                ? localizations.formatMediumDate(date)
                : entry.key;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formattedDate),
                  Text('${_formatAmount(amount)} ${challenge.unit}'),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  static String _formatAmount(double value) {
    final fixed = value.toStringAsFixed(2);
    final trimmed = fixed
        .replaceFirst(RegExp(r'\.0+\$'), '')
        .replaceFirst(RegExp(r'(\.\d*?[1-9])0+\$'), r'\1');
    return trimmed.isEmpty ? '0' : trimmed;
  }
}

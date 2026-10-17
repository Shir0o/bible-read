import '../theme/app_theme.dart';
import 'package:flutter/material.dart';

import 'app_bottom_sheet.dart';
import 'common_styles.dart';

/// The one-time choice that lets finishing a plan reading also count as
/// "showing up" for the day.
///
/// Coupling is one-directional: marking the bare daily habit never advances a
/// plan. This sheet is shown the first time a user finishes a plan reading.
///
/// Returns `true` if the user chose to link the two ("Yes, count it as showing
/// up"), `false` if they chose to keep them separate, and `null` if dismissed
/// (treated by callers the same as keeping them separate, but the choice is
/// still considered answered).
class SyncSheet extends StatelessWidget {
  const SyncSheet({super.key});

  /// Shows the sheet and resolves to the user's choice (see class docs).
  static Future<bool?> show(BuildContext context) {
    return showAppSheet<bool>(
      context: context,
      builder: (context) => const SyncSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.rInset),
                ),
                child: Icon(
                  Icons.explore_outlined,
                  color: colorScheme.onPrimaryContainer,
                  size: AppSpacing.iconLg,
                ),
              ),
              const SizedBox(width: AppSpacing.gap12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "You finished today's reading",
                      style: AppTextStyles.subtitle(context),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'One question, just this once',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'When you finish a reading from a plan, should it also count as '
            'showing up for the day? Your daily habit can stand on its own — '
            'this just saves you the second tap. (Marking “I read today” '
            'on its own never moves a plan.)',
            style: AppTextStyles.body(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.gap12),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.gap12, vertical: AppSpacing.gap12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppSpacing.rChip),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.settings_outlined,
                  size: AppSpacing.iconSm,
                  color: colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You can change this anytime in Settings › Reading '
                    'counts as showing up.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Yes, count it as showing up'),
          ),
          const SizedBox(height: AppSpacing.gap8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep them separate'),
          ),
        ],
      ),
    );
  }
}

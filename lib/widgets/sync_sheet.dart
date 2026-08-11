import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
    return showModalBottomSheet<bool>(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const SyncSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.explore_outlined,
                    color: colorScheme.onPrimaryContainer,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 13),
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
                        style: AppTextStyles.caption(
                          context,
                        ).copyWith(color: colorScheme.onSurfaceVariant),
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
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.settings_outlined,
                    size: 15,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You can change this anytime in Settings › Reading '
                      'counts as showing up.',
                      style: AppTextStyles.caption(context).copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                        height: 1.5,
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
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 9),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Keep them separate'),
            ),
          ],
        ),
      ),
    );
  }
}

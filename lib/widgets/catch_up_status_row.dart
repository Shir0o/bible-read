import 'package:flutter/material.dart';

import '../services/catch_up_engine.dart';

/// Gentle, tappable behind/on-track status row driven by a [CatchUpStatus].
///
/// Surfaced high on Home, Journey and Community (issue #720) so the catch-up
/// state the engine already computes is visible where it's useful. Tapping
/// opens the relevant schedule via [onTap].
///
/// Palette is intentionally gentle — gold (`tertiary`) for "behind", quiet
/// muted text for "on track". No red, no "overdue" framing — matching
/// `SchedulePreview`'s tone.
class CatchUpStatusRow extends StatelessWidget {
  /// Computed schedule + status from [CatchUpEngine].
  final CatchUpStatus status;

  /// Invoked when the row is tapped — should open the plan's schedule.
  final VoidCallback onTap;

  /// Leading label shown on the on-track variant. Defaults to "You're on track".
  final String onTrackLabel;

  /// Trailing action text shown on the on-track variant.
  final String onTrackAction;

  const CatchUpStatusRow({
    super.key,
    required this.status,
    required this.onTap,
    this.onTrackLabel = "You're on track",
    this.onTrackAction = 'View your schedule',
  });

  @override
  Widget build(BuildContext context) {
    // Nothing to show when there's no schedule at all.
    if (status.entries.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final behind = status.behindCount;
    final isBehind = behind > 0;

    final Color accent =
        isBehind ? colorScheme.tertiary : colorScheme.onSurfaceVariant;
    final IconData icon =
        isBehind ? Icons.refresh_rounded : Icons.calendar_today_outlined;
    final String label = isBehind
        ? '$behind reading${behind == 1 ? '' : 's'} behind'
        : onTrackLabel;
    final String action = isBehind ? 'Catch up' : onTrackAction;

    return Material(
      color: isBehind
          ? colorScheme.tertiaryContainer.withValues(alpha: 0.35)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: '  ·  $action',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

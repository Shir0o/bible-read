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

  /// Supporting subtitle shown on the on-track variant (second line).
  final String onTrackAction;

  /// Supporting subtitle shown on the behind variant (second line). The gentle,
  /// no-pressure catch-up invitation from the design — "any order, no rush".
  final String behindSubtitle;

  const CatchUpStatusRow({
    super.key,
    required this.status,
    required this.onTap,
    this.onTrackLabel = "You're on track",
    this.onTrackAction = 'View your schedule',
    this.behindSubtitle =
        'Jump to your schedule and catch up — any order, no rush',
  });

  @override
  Widget build(BuildContext context) {
    // Nothing to show when there's no schedule at all.
    if (status.entries.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final behind = status.behindCount;
    final isBehind = behind > 0;

    // Gold "behind" accent vs. quiet muted "on track" — no red, no alarm.
    final Color accent =
        isBehind ? colorScheme.tertiary : colorScheme.onSurface;
    final String title = isBehind
        ? '$behind reading${behind == 1 ? '' : 's'} behind'
        : onTrackLabel;
    final String subtitle = isBehind ? behindSubtitle : onTrackAction;

    // Leading rounded tile — a small leaf for "behind" (growth, not failure),
    // a calendar for "on track". Matches the design's PlanScheduleRow.
    final Widget leadingTile = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: isBehind ? colorScheme.tertiary : colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: isBehind
            ? null
            : Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
      ),
      alignment: Alignment.center,
      child: Icon(
        isBehind ? Icons.eco_outlined : Icons.calendar_today_outlined,
        size: 17,
        color: isBehind ? colorScheme.onTertiary : colorScheme.primary,
      ),
    );

    return Material(
      color: isBehind
          ? colorScheme.tertiaryContainer.withValues(alpha: 0.35)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              leadingTile,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: isBehind
                    ? colorScheme.tertiary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

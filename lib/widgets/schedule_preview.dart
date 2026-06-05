import 'package:flutter/material.dart';

import '../services/catch_up_engine.dart';

/// Compact, engine-driven preview of a reading plan's schedule.
///
/// Shows a small window of readings centered on where the user would resume
/// (first missed → current → first upcoming), with a pace/finish-date summary
/// header and an optional "View full schedule" action. Driven entirely by a
/// [CatchUpStatus] so it is cadence-agnostic and reusable for both personal
/// (daily) and group (weekly/irregular) plans.
class SchedulePreview extends StatelessWidget {
  /// Computed schedule + status from [CatchUpEngine].
  final CatchUpStatus status;

  /// Heading shown above the preview (e.g. the plan title or "Preview").
  final String title;

  /// When non-null, a "View full schedule" button is shown that invokes this.
  final VoidCallback? onViewFull;

  /// Number of readings to show in the windowed preview.
  final int windowSize;

  const SchedulePreview({
    super.key,
    required this.status,
    required this.title,
    this.onViewFull,
    this.windowSize = 5,
  });

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _formatDate(DateTime date) => '${_months[date.month - 1]} ${date.day}';

  String _formatDayOfWeek(DateTime date) => _weekdays[date.weekday - 1];

  /// Inclusive readings-per-week estimate derived purely from entry dates, so
  /// it is correct for daily and weekly cadences alike.
  String _paceText() {
    final entries = status.entries;
    if (entries.isEmpty) return '';
    if (entries.length == 1) return '1 reading';
    final spanDays =
        entries.last.date.difference(entries.first.date).inDays.abs();
    if (spanDays == 0) return '${entries.length} readings';
    final perWeek = entries.length / (spanDays / 7);
    final rounded = perWeek >= 1 ? perWeek.round() : 1;
    return '~$rounded reading${rounded == 1 ? '' : 's'}/week';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final entries = status.entries;

    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    // Center a window on the resume index, clamped to list bounds.
    final resume = status.resumeIndex >= 0 ? status.resumeIndex : 0;
    final count = entries.length;
    final window = windowSize.clamp(1, count);
    var start = resume - (window ~/ 2);
    if (start < 0) start = 0;
    if (start + window > count) start = count - window;
    final end = start + window;
    final earlierHidden = start;
    final laterHidden = count - end;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          const SizedBox(height: 16),
          if (earlierHidden > 0)
            _buildEllipsis(context, '$earlierHidden earlier'),
          for (var i = start; i < end; i++)
            _buildRow(context, entries[i], status.statuses[i]),
          if (laterHidden > 0) _buildEllipsis(context, '$laterHidden more'),
          if (onViewFull != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onViewFull,
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text('View full schedule'),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final entries = status.entries;
    final first = entries.first.date;
    final last = entries.last.date;

    // Gentle status line: caught up vs. how many readings behind.
    final String statusLine;
    final Color statusColor;
    if (status.inStep) {
      statusLine = 'On track';
      statusColor = colorScheme.primary;
    } else if (status.behindCount > 0) {
      final n = status.behindCount;
      statusLine = '$n reading${n == 1 ? '' : 's'} to revisit';
      statusColor = colorScheme.tertiary;
    } else {
      statusLine = '${entries.length} readings';
      statusColor = colorScheme.onSurfaceVariant;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          '${entries.length} readings · ${_paceText()}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${_formatDate(first)} – ${_formatDate(last)}, ${last.year}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          statusLine,
          style: theme.textTheme.labelMedium?.copyWith(
            color: statusColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildEllipsis(BuildContext context, String label) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Text(
        '··· $label',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    ScheduleEntry entry,
    ReadingStatus readingStatus,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isDone = readingStatus == ReadingStatus.done;
    final isCurrent = readingStatus == ReadingStatus.current;
    final isMissed = readingStatus == ReadingStatus.missed;

    // Gentle palette — no red. Missed uses tertiary (gold/amber).
    final Color accent = isCurrent
        ? colorScheme.primary
        : isMissed
            ? colorScheme.tertiary
            : colorScheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: isCurrent
            ? Border.all(color: colorScheme.primary.withValues(alpha: 0.5))
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDate(entry.date),
                  style: theme.textTheme.labelSmall?.copyWith(color: accent),
                ),
                Text(
                  _formatDayOfWeek(entry.date),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              entry.readings.join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface.withValues(alpha: 0.85),
                decoration: isDone ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildStatusMarker(context, readingStatus),
        ],
      ),
    );
  }

  Widget _buildStatusMarker(BuildContext context, ReadingStatus s) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (s) {
      case ReadingStatus.done:
        return Icon(Icons.check_circle, color: colorScheme.primary, size: 20);
      case ReadingStatus.current:
        return Icon(Icons.add_circle_outline,
            color: colorScheme.primary, size: 20);
      case ReadingStatus.missed:
        // Dashed gold ring — "to revisit", gentle.
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: colorScheme.tertiary.withValues(alpha: 0.7),
              width: 2,
            ),
          ),
        );
      case ReadingStatus.upcoming:
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
        );
    }
  }
}

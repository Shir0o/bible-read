import 'dart:async';

import 'package:flutter/material.dart';

import '../services/catch_up_engine.dart';

/// Faithful port of the design prototype's `ScheduleScreen` body
/// (`schedule.jsx`), shared by the group `FullSchedulePage` and the personal
/// `PlanDetailPage`.
///
/// Renders, top to bottom: a summary card (name + pace + progress meter + date
/// range + a "Jump to current" chip shown only when caught up), an optional
/// group "with your group" anchor, a gentle catch-up affordance (a tray for
/// groups, a quiet inline note for personal plans), an "in step" confirmation
/// (groups), and the full by-date schedule with dot-style status toggles and
/// month dividers.
///
/// Completion is forward-only: a [ReadingStatus.done] row is non-interactive
/// (no un-mark/undo), matching the design's final behavior (chat18). Everything
/// is driven by a [CatchUpStatus] from [CatchUpEngine], so it is cadence-
/// agnostic and identical for daily/personal and weekly/irregular/group plans.
class ScheduleScreenView extends StatefulWidget {
  /// Computed schedule + per-entry status from [CatchUpEngine].
  final CatchUpStatus status;

  /// Heading shown in the summary card eyebrow (plan title / group name).
  final String title;

  /// Whether this is a group plan — switches the catch-up affordance to the
  /// gentle tray, enables the "with your group" anchor and "in step" card, and
  /// adds the "· WITH GROUP" row caption.
  final bool isGroup;

  /// Invoked when a non-done row's toggle is tapped. [index] is the position in
  /// [CatchUpStatus.entries]. Never called for done rows (forward-only).
  final void Function(int index) onToggle;

  /// Builds the group "with your group" anchor card for the current reading.
  /// Only used when [isGroup] and the current reading is due-and-unread. The
  /// host supplies it because member presence requires group streams.
  final WidgetBuilder? todayAnchorBuilder;

  /// When true, every toggle is non-interactive (e.g. a non-member viewing a
  /// group's schedule).
  final bool readOnly;

  /// Optional leading widget (e.g. a plan description) rendered above the
  /// summary card.
  final Widget? header;

  const ScheduleScreenView({
    super.key,
    required this.status,
    required this.title,
    required this.isGroup,
    required this.onToggle,
    this.todayAnchorBuilder,
    this.readOnly = false,
    this.header,
  });

  @override
  State<ScheduleScreenView> createState() => _ScheduleScreenViewState();
}

class _ScheduleScreenViewState extends State<ScheduleScreenView> {
  final ScrollController _controller = ScrollController();
  final GlobalKey _resumeKey = GlobalKey();
  bool _hasScrolled = false;

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_scrollToResume(initial: true));
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ---- formatting helpers (ported from schedule.jsx) ----

  String _monShort(DateTime d) => _months[d.month - 1].substring(0, 3);
  String _weekday(DateTime d) => _weekdays[d.weekday - 1];
  String _fmtDate(DateTime d) => '${_monShort(d)} ${d.day}, ${d.year}';

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Weekly when readings are spaced ~4+ days apart (matches the group
  /// schedule's cadence heuristic), else daily.
  bool _isWeekly() {
    final entries = widget.status.entries;
    if (entries.length < 2) return false;
    final gaps = <int>[];
    for (var i = 1; i < entries.length; i++) {
      gaps.add(entries[i].date.difference(entries[i - 1].date).inDays.abs());
    }
    gaps.sort();
    return gaps[gaps.length ~/ 2] >= 4;
  }

  /// "1 reading each week" / "3 readings a day" — the prototype's `paceText`,
  /// adapted to count readings (each entry) rather than raw chapters.
  String _paceText() {
    final entries = widget.status.entries;
    if (entries.isEmpty) return '';
    // Typical readings-per-session: chapters in the first non-empty entry.
    var per = 1;
    for (final e in entries) {
      if (e.readings.isNotEmpty) {
        per = e.readings.length;
        break;
      }
    }
    final unit = per == 1 ? '1 reading' : '$per readings';
    return _isWeekly() ? '$unit each week' : '$unit a day';
  }

  /// Cadence-aware label for the current reading row.
  String _currentLabel() {
    final cur = widget.status.currentEntry;
    if (cur != null && _sameDay(cur.date, DateTime.now())) return 'Today';
    return _isWeekly() ? 'This week' : 'Current';
  }

  Future<void> _scrollToResume({bool initial = false}) async {
    if (initial && _hasScrolled) return;
    final ctx = _resumeKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    _hasScrolled = true;
    Scrollable.ensureVisible(ctx, alignment: 0.3);
    await Future.delayed(const Duration(milliseconds: 100));
    final after = _resumeKey.currentContext;
    if (after != null && after.mounted) {
      await Scrollable.ensureVisible(
        after,
        alignment: 0.1,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final entries = status.entries;

    // Whether the current reading is due-and-unread (drives the group anchor).
    final showAnchor = widget.isGroup &&
        widget.todayAnchorBuilder != null &&
        status.currentIndex >= 0 &&
        status.statuses[status.currentIndex] == ReadingStatus.current;

    final missedItems = <int>[
      for (var i = 0; i < entries.length; i++)
        if (status.statuses[i] == ReadingStatus.missed) i,
    ];

    return SingleChildScrollView(
      controller: _controller,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.header != null) ...[
            widget.header!,
            const SizedBox(height: 8),
          ],
          _buildSummaryCard(context),
          if (showAnchor) ...[
            const SizedBox(height: 14),
            widget.todayAnchorBuilder!(context),
          ],
          if (missedItems.isNotEmpty) ...[
            const SizedBox(height: 14),
            widget.isGroup
                ? _buildCatchUpTray(context, missedItems)
                : _buildCatchUpNote(context, missedItems.length),
          ],
          if (widget.isGroup && status.inStep && status.doneCount > 0) ...[
            const SizedBox(height: 14),
            _buildInStepCard(context),
          ],
          const SizedBox(height: 20),
          _buildFullScheduleHeader(context),
          const SizedBox(height: 4),
          if (entries.isEmpty)
            _buildEmpty(context)
          else
            ..._buildScheduleRows(context),
        ],
      ),
    );
  }

  // ---- summary card ----

  Widget _buildSummaryCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = widget.status;
    final entries = status.entries;
    final total = entries.length;
    final pct = total > 0 ? status.doneCount / total : 0.0;

    // "Jump to current" only when caught up (no catch-up card is showing).
    final showJump = status.missedCount == 0 && status.resumeIndex >= 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(colorScheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            _paceText(),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: pct.clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(colorScheme.primary),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${status.doneCount} of $total read',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '${_fmtDate(entries.first.date)} – '
                    '${_fmtDate(entries.last.date)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                if (showJump)
                  _Chip(
                    icon: Icons.calendar_today_outlined,
                    label: 'Jump to current',
                    onTap: () => unawaited(_scrollToResume()),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---- catch-up affordances ----

  Widget _buildCatchUpTray(BuildContext context, List<int> missedItems) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(colorScheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.eco_outlined,
                  size: 20,
                  color: colorScheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Catch up at your own pace',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      "These are still here whenever you're ready — in any "
                      'order, no rush.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 4),
          for (final i in missedItems) _buildCatchUpRow(context, i),
        ],
      ),
    );
  }

  Widget _buildCatchUpRow(BuildContext context, int i) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final entry = widget.status.entries[i];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Column(
              children: [
                Text(
                  _weekday(entry.date).toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.tertiary,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  '${entry.date.day}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.readings.join(', '),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${_monShort(entry.date)} ${entry.date.day}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          _StatusToggle(
            status: ReadingStatus.missed,
            onTap: widget.readOnly ? null : () => widget.onToggle(i),
          ),
        ],
      ),
    );
  }

  Widget _buildCatchUpNote(BuildContext context, int missed) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(colorScheme),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.eco_outlined,
              size: 18,
              color: colorScheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$missed reading${missed > 1 ? 's' : ''} to revisit',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Tap any day below to mark it read — in any order.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Chip(label: 'Jump', onTap: () => unawaited(_scrollToResume())),
        ],
      ),
    );
  }

  Widget _buildInStepCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 22, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "You're in step with your group.",
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- full schedule list ----

  Widget _buildFullScheduleHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Full schedule',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!widget.readOnly)
            Text(
              'Tap a day to mark it',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Text(
          'Choose books to generate a schedule.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }

  List<Widget> _buildScheduleRows(BuildContext context) {
    final status = widget.status;
    final entries = status.entries;
    final currentLabel = _currentLabel();
    final rows = <Widget>[];
    String? lastMonthKey;

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final monthKey = '${entry.date.year}-${entry.date.month}';
      if (monthKey != lastMonthKey) {
        lastMonthKey = monthKey;
        rows.add(_buildMonthRule(context, entry.date));
      }
      rows.add(_buildScheduleRow(context, i, currentLabel));
    }
    return rows;
  }

  Widget _buildMonthRule(BuildContext context, DateTime date) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 12),
      child: Row(
        children: [
          Text(
            '${_months[date.month - 1]} ${date.year}'.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: colorScheme.outlineVariant)),
        ],
      ),
    );
  }

  Widget _buildScheduleRow(BuildContext context, int i, String currentLabel) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final entry = widget.status.entries[i];
    final st = widget.status.statuses[i];

    final isCurrent = st == ReadingStatus.current;
    final isMissed = st == ReadingStatus.missed;
    final isDone = st == ReadingStatus.done;

    final Color dateColor = isCurrent
        ? colorScheme.primary
        : isMissed
            ? colorScheme.tertiary
            : isDone
                ? colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
                : colorScheme.onSurface;

    final bool isResume = i == widget.status.resumeIndex;

    String? caption;
    Color captionColor = colorScheme.onSurfaceVariant;
    if (isCurrent) {
      caption = widget.isGroup
          ? '${currentLabel.toUpperCase()} · WITH GROUP'
          : currentLabel.toUpperCase();
      captionColor = colorScheme.primary;
    } else if (isMissed) {
      caption = 'TO REVISIT';
      captionColor = colorScheme.tertiary;
    } else if (isDone) {
      caption = 'Read';
      captionColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
    }

    // The whole row is the tap target (the dot is a decorative indicator), so
    // marking is forgiving. Done rows are non-interactive (forward-only).
    final interactive = !widget.readOnly && !isDone;

    final inner = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Text(
                  _weekday(entry.date).toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: dateColor,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  '${entry.date.day}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: dateColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.readings.join(', '),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: isDone
                        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
                        : colorScheme.onSurface,
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    caption,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: captionColor,
                      fontWeight: isDone ? FontWeight.w600 : FontWeight.w700,
                      letterSpacing: isDone ? 0 : 0.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusToggle(status: st),
        ],
      ),
    );

    return Container(
      key: isResume ? _resumeKey : null,
      margin: const EdgeInsets.only(bottom: 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isCurrent
            ? colorScheme.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent
              ? colorScheme.primary.withValues(alpha: 0.25)
              : Colors.transparent,
        ),
      ),
      child: InkWell(
        onTap: interactive ? () => widget.onToggle(i) : null,
        child: inner,
      ),
    );
  }

  BoxDecoration _cardDecoration(ColorScheme colorScheme) => BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant, width: 0.5),
      );
}

/// A single tappable status dot, ported from the design's `StatusToggle`.
///
///   • done     — filled primary circle with a check (non-interactive)
///   • current  — soft primary circle with a plus
///   • missed   — tertiary (gold) dashed-style ring with a plus
///   • upcoming — quiet outline ring
class _StatusToggle extends StatelessWidget {
  final ReadingStatus status;
  final VoidCallback? onTap;

  const _StatusToggle({required this.status, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const ring = 26.0;

    Widget inner;
    switch (status) {
      case ReadingStatus.done:
        inner = Container(
          width: ring,
          height: ring,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primary,
          ),
          child: Icon(Icons.check, size: 15, color: colorScheme.onPrimary),
        );
        break;
      case ReadingStatus.current:
        inner = Container(
          width: ring,
          height: ring,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primaryContainer,
            border:
                Border.all(color: colorScheme.primary.withValues(alpha: 0.5)),
          ),
          child: Icon(Icons.add, size: 16, color: colorScheme.primary),
        );
        break;
      case ReadingStatus.missed:
        inner = Container(
          width: ring,
          height: ring,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colorScheme.tertiary, width: 2),
          ),
          child: Icon(Icons.add, size: 14, color: colorScheme.tertiary),
        );
        break;
      case ReadingStatus.upcoming:
        inner = Center(
          child: Container(
            width: ring - 11,
            height: ring - 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
          ),
        );
        break;
    }

    if (onTap == null) {
      return SizedBox(width: ring, height: ring, child: inner);
    }
    return InkResponse(
      onTap: onTap,
      radius: ring,
      child: SizedBox(width: ring, height: ring, child: inner),
    );
  }
}

/// Small pill button matching the design's `.chip` (used for "Jump…").
class _Chip extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

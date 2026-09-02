import 'package:flutter/material.dart';

import '../models/group_schedule.dart';
import '../services/reference_parser.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import 'common_styles.dart';
import 'group_plan_keys.dart';
import 'stepper_control.dart';

const List<String> _months = [
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

const List<String> _weekdays = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// Formats a date the way the rest of the app reads dates: `Tue, Sep 1`.
String formatPlanDate(DateTime date) =>
    '${_weekdays[date.weekday - 1]}, ${_months[date.month - 1]} ${date.day}';

/// Short form for summary tiles: `Sep 1`.
String formatPlanDateShort(DateTime date) =>
    '${_months[date.month - 1]} ${date.day}';

/// Renders a day's chapters the way they are read aloud: consecutive chapters
/// of one book collapse to a range, and a day spanning two books names both.
///
/// `['Jeremiah 2', 'Jeremiah 3']` becomes `Jeremiah 2–3`, and
/// `['Jeremiah 52', 'Lamentations 1']` becomes `Jeremiah 52 · Lamentations 1`.
String formatChapterRun(List<String> chapters) {
  if (chapters.isEmpty) return '';

  final runs = <({String book, int start, int end})>[];
  for (final reference in chapters) {
    final book = ReferenceParser.parseBook(reference);
    final chapter = int.tryParse(
        RegExp(r'(\d+)\s*$').firstMatch(reference)?.group(1) ?? '');
    if (book == null || chapter == null) {
      // Unparseable entries are shown verbatim rather than dropped.
      runs.add((book: reference, start: -1, end: -1));
      continue;
    }
    final last = runs.isEmpty ? null : runs.last;
    if (last != null && last.book == book && last.end == chapter - 1) {
      runs[runs.length - 1] = (book: book, start: last.start, end: chapter);
    } else {
      runs.add((book: book, start: chapter, end: chapter));
    }
  }

  return runs.map((r) {
    if (r.start < 0) return r.book;
    return r.start == r.end
        ? '${r.book} ${r.start}'
        : '${r.book} ${r.start}–${r.end}';
  }).join(' · ');
}

/// The days of a plan, each adjustable in place.
///
/// Stepping one day reflows every day after it, so the reading stays in order.
/// Shared by the create form (showing the first few days) and the full
/// adjust-days screen (showing all of them).
class PlanDayList extends StatelessWidget {
  final List<GroupSchedule> days;

  /// Day indices whose length the reader set by hand.
  final Set<int> overriddenDays;

  /// Called with a day index and the count it should hold.
  final void Function(int dayIndex, int count) onSetCount;

  /// Rows to render. Null shows every day.
  final int? maxRows;

  /// Shown under the rows — typically how many days are not listed.
  final Widget? footer;

  final VibrationService vibrationService;

  const PlanDayList({
    super.key,
    required this.days,
    required this.overriddenDays,
    required this.onSetCount,
    this.maxRows,
    this.footer,
    this.vibrationService = const VibrationService(),
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);
    final shown = maxRows == null
        ? days.length
        : (maxRows! < days.length ? maxRows! : days.length);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(color: appColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < shown; i++)
            _DayRow(
              index: i,
              day: days[i],
              edited: overriddenDays.contains(i),
              showDivider: i > 0,
              onSetCount: onSetCount,
              vibrationService: vibrationService,
            ),
          if (footer != null) footer!,
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  final int index;
  final GroupSchedule day;
  final bool edited;
  final bool showDivider;
  final void Function(int dayIndex, int count) onSetCount;
  final VibrationService vibrationService;

  const _DayRow({
    required this.index,
    required this.day,
    required this.edited,
    required this.showDivider,
    required this.onSetCount,
    required this.vibrationService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);

    return Container(
      key: GroupPlanKeys.dayRow(index),
      decoration: showDivider
          ? BoxDecoration(
              border: Border(top: BorderSide(color: appColors.border)),
            )
          : null,
      padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 7,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'DAY ${index + 1}',
                      style: AppTextStyles.eyebrow(context).copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                    Text(
                      formatPlanDate(day.date),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (edited)
                      Container(
                        key: GroupPlanKeys.daySetTag(index),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: appColors.accentSoft,
                          borderRadius: BorderRadius.circular(AppSpacing.rChip),
                        ),
                        child: Text(
                          'SET',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10.5,
                            letterSpacing: 0.6,
                            color: colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  formatChapterRun(day.chapters),
                  style: TextStyle(
                    fontFamily: AppTheme.fontSerif,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                    height: 1.3,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.gap12),
          StepperControl(
            value: day.chapters.length,
            size: StepperSize.compact,
            decrementKey: GroupPlanKeys.dayStepperDec(index),
            incrementKey: GroupPlanKeys.dayStepperInc(index),
            decrementLabel: 'One chapter fewer on day ${index + 1}',
            incrementLabel: 'One chapter more on day ${index + 1}',
            vibrationService: vibrationService,
            onChanged: (count) => onSetCount(index, count),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'common_styles.dart';

/// Displays a month streak calendar with arrow navigation.
class MonthStreakCalendar extends StatelessWidget {
  /// Set of dates the user has read.
  final Set<DateTime> readDates;

  /// Month being displayed.
  final DateTime month;

  /// Whether navigation arrows are shown.
  final bool showNavigation;

  /// Callback when the previous month arrow is pressed.
  final VoidCallback? onPrevious;

  /// Callback when the next month arrow is pressed.
  final VoidCallback? onNext;

  const MonthStreakCalendar({
    super.key,
    required this.readDates,
    required this.month,
    this.showNavigation = true,
    this.onPrevious,
    this.onNext,
  });

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isCurrentMonth() {
    final now = DateTime.now();
    return now.year == month.year && now.month == month.month;
  }

  String _monthName(int month) {
    const months = [
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
    return months[month - 1];
  }

  List<TableRow> _buildRows(ColorScheme colorScheme) {
    final firstDay = DateTime(month.year, month.month, 1);
    final totalDays = DateTime(month.year, month.month + 1, 0).day;
    final weekdayOffset = firstDay.weekday % 7;

    final rows = <TableRow>[];
    final totalCells = totalDays + weekdayOffset;
    final totalWeeks = (totalCells / 7).ceil();

    for (int w = 0; w < totalWeeks; w++) {
      final List<Widget> weekWidgets = [];
      for (int d = 0; d < 7; d++) {
        final cellIndex = w * 7 + d;
        final day = cellIndex - weekdayOffset + 1;

        if (day < 1 || day > totalDays) {
          weekWidgets.add(const SizedBox.shrink());
        } else {
          final date = DateTime(month.year, month.month, day);
          final filled = readDates.any((d) => _isSameDay(d, date));
          weekWidgets.add(
            Semantics(
              label:
                  '${_monthName(month.month)} $day, ${filled ? "Read" : "Not read"}',
              excludeSemantics: true,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                alignment: Alignment.center,
                child: Tooltip(
                  message: filled ? 'Read' : 'Not read',
                  child: Icon(
                    filled ? Icons.circle : Icons.circle_outlined,
                    size: 16,
                    color: filled
                        ? colorScheme.primary
                        : colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
          );
        }
      }
      rows.add(TableRow(children: weekWidgets));
    }

    return rows;
  }

  String get _monthLabel => '${month.year} – ${_monthName(month.month)}';

  @override
  Widget build(BuildContext context) {
    return CommonStyles.buildCard(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showNavigation)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Previous month',
                  onPressed: onPrevious,
                ),
              Flexible(
                child: Text(
                  _monthLabel,
                  style: AppTextStyles.body(context)
                      .copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showNavigation)
                IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  tooltip: 'Next month',
                  onPressed: _isCurrentMonth() ? null : onNext,
                ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Table(
                  // Removed defaultColumnWidth to allow flexible sizing
                  children: [
                    TableRow(
                      children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                          .map(
                            (d) => Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                d,
                                style: AppTextStyles.body(context).copyWith(
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    ..._buildRows(Theme.of(context).colorScheme),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

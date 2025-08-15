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

  List<TableRow> _buildRows() {
    final firstDay = DateTime(month.year, month.month, 1);
    final totalDays = DateTime(month.year, month.month + 1, 0).day;
    final weekdayOffset = firstDay.weekday % 7;

    final rows = <TableRow>[];
    for (int i = 0; i < ((totalDays + weekdayOffset + 6) / 7).floor(); i++) {
      rows.add(TableRow(children: List.filled(7, const SizedBox.shrink())));
    }

    for (int day = 1; day <= totalDays; day++) {
      final date = DateTime(month.year, month.month, day);
      final filled = readDates.any((d) => _isSameDay(d, date));
      final index = weekdayOffset + day - 1;
      final weekRow = index ~/ 7;
      final weekdayIndex = index % 7;
      rows[weekRow].children[weekdayIndex] = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Icon(
            filled ? Icons.circle : Icons.circle_outlined,
            size: 12,
            color: filled ? Colors.green : Colors.grey,
          ),
        ),
      );
    }

    return rows;
  }

  String get _monthLabel => '${month.year} – ${_monthName(month.month)}';

  @override
  Widget build(BuildContext context) {
    return CommonStyles.buildCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showNavigation)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onPrevious,
                ),
              Text(
                _monthLabel,
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
              ),
              if (showNavigation)
                IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _isCurrentMonth() ? null : onNext,
                ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Table(
                defaultColumnWidth: const FixedColumnWidth(32),
                children: [
                  TableRow(
                    children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                        .map(
                          (d) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Center(
                              child: Text(
                                d,
                                style: AppTextStyles.body.copyWith(
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  ..._buildRows(),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

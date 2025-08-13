import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'common_styles.dart';

/// Displays a month streak calendar for the current month.
class MonthStreakCalendar extends StatelessWidget {
  /// Set of dates the user has read.
  final Set<DateTime> readDates;

  const MonthStreakCalendar({super.key, required this.readDates});

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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

  List<TableRow> _buildRows(DateTime now) {
    final firstDay = DateTime(now.year, now.month, 1);
    final totalDays = DateTime(now.year, now.month + 1, 0).day;
    final weekdayOffset = firstDay.weekday % 7;

    final rows = <TableRow>[];
    for (int i = 0; i < ((totalDays + weekdayOffset + 6) / 7).floor(); i++) {
      rows.add(TableRow(children: List.filled(7, const SizedBox.shrink())));
    }

    for (int day = 1; day <= totalDays; day++) {
      final date = DateTime(now.year, now.month, day);
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthLabel = '${now.year} – ${_monthName(now.month)}';

    return CommonStyles.buildCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            monthLabel,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
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
                  ..._buildRows(now),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

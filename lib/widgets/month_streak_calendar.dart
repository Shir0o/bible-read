import 'package:flutter/material.dart';

import 'common_styles.dart';

/// Displays a month streak calendar with arrow navigation.
class MonthStreakCalendar extends StatefulWidget {
  /// Set of dates the user has read.
  final Set<DateTime> readDates;

  /// Whether navigation arrows are shown.
  final bool showNavigation;

  const MonthStreakCalendar({
    super.key,
    required this.readDates,
    this.showNavigation = true,
  });

  @override
  State<MonthStreakCalendar> createState() => _MonthStreakCalendarState();
}

class _MonthStreakCalendarState extends State<MonthStreakCalendar> {
  late DateTime _currentMonth;

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month);
  }

  bool _isCurrentMonth() {
    final now = DateTime.now();
    return now.year == _currentMonth.year && now.month == _currentMonth.month;
  }

  void _prevMonth() {
    if (!widget.showNavigation) return;
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
  }

  void _nextMonth() {
    if (!widget.showNavigation || _isCurrentMonth()) return;
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    });
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
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final totalDays =
        DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final weekdayOffset = firstDay.weekday % 7;

    final rows = <TableRow>[];
    for (int i = 0; i < ((totalDays + weekdayOffset + 6) / 7).floor(); i++) {
      rows.add(TableRow(children: List.filled(7, const SizedBox.shrink())));
    }

    for (int day = 1; day <= totalDays; day++) {
      final date = DateTime(_currentMonth.year, _currentMonth.month, day);
      final filled = widget.readDates.any((d) => _isSameDay(d, date));
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
    final monthLabel =
        '${_currentMonth.year} – ${_monthName(_currentMonth.month)}';

    return CommonStyles.buildCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.showNavigation)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _prevMonth,
                ),
              Text(
                monthLabel,
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
              ),
              if (widget.showNavigation)
                IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _isCurrentMonth() ? null : _nextMonth,
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

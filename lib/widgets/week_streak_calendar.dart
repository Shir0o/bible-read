import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'common_styles.dart';

/// Displays a week streak calendar with arrow navigation.
class WeekStreakCalendar extends StatefulWidget {
  /// Set of dates the user has read.
  final Set<DateTime> readDates;

  const WeekStreakCalendar({super.key, required this.readDates});

  @override
  State<WeekStreakCalendar> createState() => _WeekStreakCalendarState();
}

class _WeekStreakCalendarState extends State<WeekStreakCalendar> {
  late DateTime _sunday;

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _sunday = now.subtract(Duration(days: now.weekday % 7));
  }

  bool _isCurrentWeek() {
    final now = DateTime.now();
    final currentSunday = now.subtract(Duration(days: now.weekday % 7));
    return _isSameDay(_sunday, currentSunday);
  }

  void _prevWeek() {
    setState(() {
      _sunday = _sunday.subtract(const Duration(days: 7));
    });
  }

  void _nextWeek() {
    if (_isCurrentWeek()) return;
    setState(() {
      _sunday = _sunday.add(const Duration(days: 7));
    });
  }

  @override
  Widget build(BuildContext context) {
    final weekOf = '${_sunday.month}/${_sunday.day}';
    const days = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return CommonStyles.buildCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _prevWeek,
              ),
              Text(
                'Week of $weekOf',
                style:
                    AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: _isCurrentWeek() ? null : _nextWeek,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(7, (i) {
              final date = _sunday.add(Duration(days: i));
              final filled =
                  widget.readDates.any((d) => _isSameDay(d, date));
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  children: [
                    Text(
                      days[i],
                      style: AppTextStyles.body.copyWith(fontSize: 10),
                    ),
                    const SizedBox(height: 4),
                    Icon(
                      filled
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: filled ? Colors.green : Colors.grey,
                      size: 20,
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

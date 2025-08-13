import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'common_styles.dart';

/// Displays a week streak calendar for the current week.
class WeekStreakCalendar extends StatelessWidget {
  /// Set of dates the user has read.
  final Set<DateTime> readDates;

  const WeekStreakCalendar({super.key, required this.readDates});

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sunday = now.subtract(Duration(days: now.weekday % 7));
    final weekOf = '${sunday.month}/${sunday.day}';
    const days = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return CommonStyles.buildCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Week of $weekOf',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(7, (i) {
              final date = sunday.add(Duration(days: i));
              final filled = readDates.any((d) => _isSameDay(d, date));
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

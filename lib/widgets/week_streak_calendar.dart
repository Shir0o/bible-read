import 'package:flutter/material.dart';

import 'common_styles.dart';

/// Displays a week streak calendar with arrow navigation.
class WeekStreakCalendar extends StatelessWidget {
  /// Set of dates the user has read.
  final Set<DateTime> readDates;

  /// The Sunday that starts the displayed week.
  final DateTime sunday;

  /// Whether to show navigation arrows and allow week changes.
  final bool showNavigation;

  /// Callback when the previous week arrow is pressed.
  final VoidCallback? onPrevious;

  /// Callback when the next week arrow is pressed.
  final VoidCallback? onNext;

  const WeekStreakCalendar({
    super.key,
    required this.readDates,
    required this.sunday,
    this.showNavigation = true,
    this.onPrevious,
    this.onNext,
  });

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _normalize(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _isCurrentWeek() {
    final now = DateTime.now();
    final normalizedNow = _normalize(now);
    final currentSunday = DateTime(
      normalizedNow.year,
      normalizedNow.month,
      normalizedNow.day - (normalizedNow.weekday % 7),
    );
    return _isSameDay(_normalize(sunday), currentSunday);
  }

  String get _weekLabel => '${sunday.month}/${sunday.day}';

  @override
  Widget build(BuildContext context) {
    const days = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

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
                  onPressed: onPrevious,
                ),
              Text(
                'Week of $_weekLabel',
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
              ),
              if (showNavigation)
                IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _isCurrentWeek() ? null : onNext,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(7, (i) {
              final date = DateTime(
                sunday.year,
                sunday.month,
                sunday.day + i,
              );
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

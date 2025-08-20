import 'package:flutter/material.dart';

import 'common_styles.dart';
import 'month_streak_calendar.dart';
import 'read_switch_tile.dart';
import 'week_streak_calendar.dart';

/// Displays the user's read toggle and streak calendars.
class ReadStatusSection extends StatelessWidget {
  /// Whether to show a loading indicator for the toggle.
  final bool toggleLoading;

  /// Whether the user has marked today as read.
  final bool readToday;

  /// Callback when the user toggles the read switch.
  final VoidCallback? onToggle;

  /// Dates that the user has read.
  final Set<DateTime> readDates;

  const ReadStatusSection({
    super.key,
    required this.toggleLoading,
    required this.readToday,
    this.onToggle,
    required this.readDates,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sunday = now.subtract(Duration(days: now.weekday % 7));
    final month = DateTime(now.year, now.month);

    return Column(
      children: [
        CommonStyles.buildCard(
          child: toggleLoading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Mark today as read'),
                    ReadSwitchTile(
                      value: readToday,
                      onChanged: readToday ? null : (_) => onToggle?.call(),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        IgnorePointer(
          child: WeekStreakCalendar(
            readDates: readDates,
            sunday: sunday,
            showNavigation: false,
          ),
        ),
        const SizedBox(height: 16),
        IgnorePointer(
          child: MonthStreakCalendar(
            readDates: readDates,
            month: month,
            showNavigation: false,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import 'common_styles.dart';
import 'month_streak_calendar.dart';
import 'read_switch_tile.dart';
import 'week_streak_calendar.dart';
import '../services/vibration_service.dart';

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

  /// Service used for toggle vibrations.
  final VibrationService vibrationService;

  const ReadStatusSection({
    super.key,
    required this.toggleLoading,
    required this.readToday,
    this.onToggle,
    required this.readDates,
    VibrationService? vibrationService,
  }) : vibrationService = vibrationService ?? const VibrationService();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sunday = now.subtract(Duration(days: now.weekday % 7));
    final month = DateTime(now.year, now.month);

    final bool canToggle = !toggleLoading && !readToday && onToggle != null;

    return Column(
      children: [
        CommonStyles.buildTappableCard(
          onTap: toggleLoading
              ? null
              : (canToggle ? onToggle : () => _showLockedSnackBar(context)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: toggleLoading
                ? const Center(
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : SizedBox(
                    width: double.infinity,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 12),
                          child: Text('Mark today as read'),
                        ),
                        const SizedBox(width: 12),
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: ReadSwitchTile(
                            value: readToday,
                            onChanged: (readToday || onToggle == null)
                                ? (_) => _showLockedSnackBar(context)
                                : (_) => onToggle?.call(),
                            vibrationService: vibrationService,
                          ),
                        ),
                      ],
                    ),
                  ),
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

  static void _showLockedSnackBar(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Already marked today. Come back tomorrow!'),
      ),
    );
  }
}

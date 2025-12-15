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

  /// Remaining streak freezes (grace credits) for the current month.
  final int? streakFreezesLeft;

  static const _streakFreezeDescription =
      'Each month includes two automatic grace credits to freeze a missed day. '
      'Every 15-day streak earns one extra credit.';

  const ReadStatusSection({
    super.key,
    required this.toggleLoading,
    required this.readToday,
    this.onToggle,
    required this.readDates,
    this.streakFreezesLeft,
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
          context: context,
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
        if (streakFreezesLeft != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Streak freezes left: $streakFreezesLeft',
                    style: AppTextStyles.body,
                  ),
                  Tooltip(
                    message: _streakFreezeDescription,
                    child: IconButton(
                      padding: const EdgeInsets.only(left: 4),
                      constraints: const BoxConstraints(),
                      iconSize: 18,
                      icon: const Icon(Icons.info_outline),
                      onPressed: () => _showStreakFreezeInfo(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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

  static void _showStreakFreezeInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Streak freezes'),
          content: const Text(
            _streakFreezeDescription,
            style: AppTextStyles.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }
}

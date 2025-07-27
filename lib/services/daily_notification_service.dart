import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/notification_preferences.dart';
import 'notification_preferences_service.dart';

/// Simple representation of a time of day.
class Time {
  /// Hour component in 24h format.
  final int hour;

  /// Minute component.
  final int minute;

  /// Second component, defaults to 0.
  final int second;

  /// Creates a [Time] instance.
  const Time(this.hour, this.minute, [this.second = 0]);
}

/// Schedules and cancels the daily reminder notification.
class DailyNotificationService {
  /// Notification plugin used to schedule messages.
  final FlutterLocalNotificationsPlugin plugin;

  /// Service for reading notification preferences.
  final NotificationPreferencesService prefsService;

  /// Auth instance for identifying the current user.
  final FirebaseAuth auth;

  bool _tzInitialized = false;

  /// ID used for the daily reminder notification.
  static const int _id = 1000;

  /// Creates a [DailyNotificationService].
  DailyNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    NotificationPreferencesService? prefsService,
    FirebaseAuth? auth,
  })  : plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        prefsService = prefsService ?? NotificationPreferencesService(),
        auth = auth ?? FirebaseAuth.instance;

  Future<void> _ensureTzInitialized() async {
    if (_tzInitialized) return;
    tz.initializeTimeZones();
    _tzInitialized = true;
  }

  /// Schedule a daily reminder notification at the given [time].
  Future<void> scheduleDailyReminder(Time time) async {
    await _ensureTzInitialized();
    final user = auth.currentUser;
    if (user == null) return;
    final prefs = await prefsService.fetchPreferences(user.uid);
    if (!prefs[NotificationType.dailyReminder]) return;

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
      time.second,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_reminder',
        'Daily Reminder',
        importance: Importance.defaultImportance,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await plugin.zonedSchedule(
      _id,
      'Bible Reading Reminder',
      "Don't forget to log your reading today!",
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Cancel any pending daily reminder notification.
  Future<void> cancelDailyReminder() async {
    await plugin.cancel(_id);
  }
}

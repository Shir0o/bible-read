import 'package:bible_read/services/daily_notification_service.dart';
import 'package:bible_read/services/notification_preferences_service.dart';
import 'package:bible_read/models/notification_preferences.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class FakeNotificationsPlugin implements FlutterLocalNotificationsPlugin {
  int? scheduledId;
  int? cancelId;
  DateTimeComponents? components;
  tz.TZDateTime? scheduledDate;

  @override
  Future<void> zonedSchedule(
    int id,
    String? title,
    String? body,
    tz.TZDateTime scheduledDate,
    NotificationDetails notificationDetails, {
    required AndroidScheduleMode androidScheduleMode,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    scheduledId = id;
    components = matchDateTimeComponents;
    this.scheduledDate = scheduledDate;
  }

  @override
  Future<void> cancel(int id, {String? tag}) async {
    cancelId = id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  group('DailyNotificationService', () {
    late FakeFirebaseFirestore firestore;
    late NotificationPreferencesService prefsService;
    late FakeNotificationsPlugin plugin;
    late MockFirebaseAuth auth;
    late DailyNotificationService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      prefsService = NotificationPreferencesService(firestore: firestore);
      plugin = FakeNotificationsPlugin();
      auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
      service = DailyNotificationService(
        plugin: plugin,
        prefsService: prefsService,
        auth: auth,
      );
    });

    test('schedules when preference enabled', () async {
      await prefsService.updatePreference(
        'u1',
        NotificationType.dailyReminder,
        true,
      );
      await service.scheduleDailyReminder(const Time(8, 0));
      expect(plugin.scheduledId, isNotNull);
      expect(plugin.components, DateTimeComponents.time);
      expect(plugin.scheduledDate?.hour, 8);
    });

    test('does nothing when preference disabled', () async {
      await prefsService.updatePreference(
        'u1',
        NotificationType.dailyReminder,
        false,
      );
      await service.scheduleDailyReminder(const Time(8, 0));
      expect(plugin.scheduledId, isNull);
    });

    test('cancel cancels notification', () async {
      await service.cancelDailyReminder();
      expect(plugin.cancelId, 1000);
    });
  });
}

import 'package:bible_read/services/daily_notification_service.dart';
import 'package:bible_read/services/notification_preferences_service.dart';
import 'package:bible_read/models/notification_preferences.dart';
import 'package:bible_read/services/error_logger.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class MockNotificationsPlugin implements FlutterLocalNotificationsPlugin {
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

class MockCrashlytics extends Mock implements FirebaseCrashlytics {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  setupFirebaseCoreMocks();
  const MethodChannel timezoneChannel = MethodChannel('flutter_timezone');

  group('DailyNotificationService', () {
    late FakeFirebaseFirestore firestore;
    late NotificationPreferencesService prefsService;
    late MockNotificationsPlugin plugin;
    late MockFirebaseAuth auth;
    late DailyNotificationService service;
    late MockCrashlytics crashlytics;

    setUpAll(() async {
      await Firebase.initializeApp();
    });

    setUp(() {
      firestore = FakeFirebaseFirestore();
      prefsService = NotificationPreferencesService(firestore: firestore);
      plugin = MockNotificationsPlugin();
      auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
      service = DailyNotificationService(
        plugin: plugin,
        prefsService: prefsService,
        auth: auth,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            timezoneChannel,
            (MethodCall call) async => 'America/Detroit',
          );
      tz.setLocalLocation(tz.getLocation('UTC'));
      crashlytics = MockCrashlytics();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(timezoneChannel, null);
    });

    test('scheduleDailyReminder calls plugin with correct values', () async {
      await prefsService.updatePreference(
        'u1',
        NotificationType.dailyReminder,
        true,
      );
      await service.scheduleDailyReminder(const Time(8, 0));
      expect(plugin.scheduledId, 1000);
      expect(plugin.components, DateTimeComponents.time);
      expect(plugin.scheduledDate?.hour, 8);
      expect(plugin.scheduledDate?.minute, 0);
    });

    test('scheduleDailyReminder respects device timezone', () async {
      await prefsService.updatePreference(
        'u1',
        NotificationType.dailyReminder,
        true,
      );
      await service.scheduleDailyReminder(const Time(8, 0));
      expect(plugin.scheduledDate?.location.name, 'America/Detroit');
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

    test('returns false when user not signed in', () async {
      auth = MockFirebaseAuth(signedIn: false);
      service = DailyNotificationService(
        plugin: plugin,
        prefsService: prefsService,
        auth: auth,
      );
      final result = await service.scheduleDailyReminder(const Time(8, 0));
      expect(result, isFalse);
      expect(plugin.scheduledId, isNull);
    });

    test('rolls scheduled date to next day if time before now', () async {
      await prefsService.updatePreference(
        'u1',
        NotificationType.dailyReminder,
        true,
      );
      final now = tz.TZDateTime.now(tz.local);
      await service.scheduleDailyReminder(const Time(0, 0));
      final scheduled = plugin.scheduledDate!;
      final expectedNextDay = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
      ).add(const Duration(days: 1));
      expect(scheduled.year, expectedNextDay.year);
      expect(scheduled.month, expectedNextDay.month);
      expect(scheduled.day, expectedNextDay.day);
    });

    test('logs and returns false when scheduling throws', () async {
      await prefsService.updatePreference(
        'u1',
        NotificationType.dailyReminder,
        true,
      );
      ErrorLogger.crashlytics = crashlytics;
      when(
        () => crashlytics.recordError(
          any(),
          any(),
          reason: any(named: 'reason'),
          information: any(named: 'information'),
          printDetails: any(named: 'printDetails'),
          fatal: any(named: 'fatal'),
        ),
      ).thenAnswer((_) async {});
      final throwingPlugin = _ThrowingNotificationsPlugin();
      service = DailyNotificationService(
        plugin: throwingPlugin,
        prefsService: prefsService,
        auth: auth,
      );

      final result = await service.scheduleDailyReminder(const Time(8, 0));

      expect(result, isFalse);
      verify(
        () => crashlytics.recordError(
          any(),
          any(),
          reason: any(named: 'reason'),
          information: any(named: 'information'),
          printDetails: any(named: 'printDetails'),
          fatal: any(named: 'fatal'),
        ),
      ).called(1);
    });

    test('cancelDailyReminder cancels notification', () async {
      await service.cancelDailyReminder();
      expect(plugin.cancelId, 1000);
    });
  });
}

class _ThrowingNotificationsPlugin extends MockNotificationsPlugin {
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
    throw Exception('boom');
  }
}

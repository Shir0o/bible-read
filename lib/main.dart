import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:bible_read/pages/friend_requests_page.dart';
import 'package:bible_read/pages/group_join_requests_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'services/error_logger.dart';
import 'services/reminder_service.dart';
import 'services/friend_service.dart';
import 'services/group_service.dart';
import 'theme/app_theme.dart';

// Global flag to skip messaging setup, useful for integration tests to avoid
// system permission dialogs that block the UI.
bool skipMessagingSetup = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Log whether the app is running in debug mode.
  debugPrint('kDebugMode: $kDebugMode');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  bool appCheckFailed = false;
  try {
    if (kDebugMode) {
      await FirebaseAppCheck.instance.activate(
        androidProvider: AndroidProvider.debug,
        appleProvider: AppleProvider.debug,
      );
      // Try to get token to trigger debug token print in logs
      try {
        final token = await FirebaseAppCheck.instance.getToken();
        debugPrint('Firebase App Check debug token: $token');
      } catch (e) {
        debugPrint('AppCheck getToken failed (normal for simulators): $e');
        debugPrint('TIP: If using an emulator, you may need to add a Debug Token in the Firebase Console under App Check.');
      }
    } else {
      await FirebaseAppCheck.instance.activate(
        androidProvider: AndroidProvider.playIntegrity,
        appleProvider: AppleProvider.appAttest,
      );
    }
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('AppCheck activation failed (non-fatal in debug): $e\n$st');
    } else {
      ErrorLogger.log(e, st);
      try {
        await FirebaseFirestore.instance.collection('app_check_errors').add({
          'timestamp': Timestamp.now(),
          'error': e.toString(),
          'stack': st.toString(),
          'platform': defaultTargetPlatform.toString(),
        });
      } catch (firestoreError, st) {
        ErrorLogger.log(firestoreError, st);
      }
      appCheckFailed = true;
    }
  }
  await FirebaseCrashlytics.instance
      .setCrashlyticsCollectionEnabled(!kDebugMode);

  FlutterError.onError = (details) {
    if (kDebugMode) {
      FlutterError.dumpErrorToConsole(details);
    }
    ErrorLogger.log(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorLogger.log(error, stack);
    return true;
  };

  if (!skipMessagingSetup) {
    await _setupMessaging();
  }
  runApp(MyApp(appCheckFailed: appCheckFailed));
}

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

class NotificationNavigator {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  NotificationNavigator({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance;

  Future<void> handleMessage(RemoteMessage message) async {
    if (message.data.isEmpty) return;
    await navigateForData(message.data);
  }

  Future<void> handlePayload(String? payload) async {
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        final normalized = <String, dynamic>{};
        decoded.forEach((key, value) {
          if (value != null) {
            normalized['$key'] = value.toString();
          }
        });
        await navigateForData(normalized);
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Failed to handle notification payload: $error');
      }
      await ErrorLogger.log(error, stackTrace);
    }
  }

  Future<void> navigateForData(Map<String, dynamic> data) async {
    final navigator = _rootNavigatorKey.currentState;
    if (navigator == null) {
      if (kDebugMode) {
        debugPrint('Navigator not ready for notification tap.');
      }
      return;
    }

    final type = data['type']?.toString();
    if (type == null) {
      if (kDebugMode) {
        debugPrint('Notification payload missing type.');
      }
      return;
    }

    switch (type) {
      case 'friendRequest':
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => FriendRequestsPage(
              auth: auth,
              friendService: FriendService(firestore: firestore),
            ),
          ),
        );
        break;
      case 'groupJoinRequest':
        final groupId = data['groupId']?.toString();
        if (groupId == null || groupId.isEmpty) {
          if (kDebugMode) {
            debugPrint('Missing groupId for group join notification.');
          }
          return;
        }
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => GroupJoinRequestsPage(
              groupId: groupId,
              auth: auth,
              groupService: GroupService(firestore: firestore),
            ),
          ),
        );
        break;
      default:
        if (kDebugMode) {
          debugPrint('Unhandled notification type: $type');
        }
        break;
    }
  }
}

// Global instance for convenience, can be overridden in tests.
NotificationNavigator notificationNavigator = NotificationNavigator();

Future<void> _setupMessaging() async {
  final messaging = FirebaseMessaging.instance;
  if (kDebugMode) {
    // Don't block on permission in debug/tests to avoid hanging on system dialogs
    unawaited(messaging.requestPermission().catchError((e) {
      debugPrint('Permission request failed: $e');
      return const NotificationSettings(
        alert: AppleNotificationSetting.disabled,
        announcement: AppleNotificationSetting.disabled,
        authorizationStatus: AuthorizationStatus.notDetermined,
        badge: AppleNotificationSetting.disabled,
        carPlay: AppleNotificationSetting.disabled,
        lockScreen: AppleNotificationSetting.disabled,
        notificationCenter: AppleNotificationSetting.disabled,
        showPreviews: AppleShowPreviewSetting.never,
        sound: AppleNotificationSetting.disabled,
        timeSensitive: AppleNotificationSetting.disabled,
        criticalAlert: AppleNotificationSetting.disabled,
        providesAppNotificationSettings: AppleNotificationSetting.disabled,
      );
    }));
  } else {
    await messaging.requestPermission();
  }

  await ReminderService().init(
    onDidReceiveNotificationResponse: (response) async {
      await notificationNavigator.handlePayload(response.payload);
    },
  );

  final notificationLaunchDetails = await ReminderService()
      .flutterLocalNotificationsPlugin
      .getNotificationAppLaunchDetails();
  final launchPayload =
      notificationLaunchDetails?.notificationResponse?.payload;
  if ((notificationLaunchDetails?.didNotificationLaunchApp ?? false) &&
      launchPayload != null &&
      launchPayload.isNotEmpty) {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      unawaited(notificationNavigator.handlePayload(launchPayload));
    });
  }

  FirebaseMessaging.onMessage.listen((message) async {
    final notification = message.notification;
    if (notification != null) {
      final payload = message.data.isEmpty ? null : jsonEncode(message.data);
      await ReminderService().flutterLocalNotificationsPlugin.show(
            notification.hashCode,
            notification.title,
            notification.body,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'default_channel',
                'Notifications',
                importance: Importance.defaultImportance,
              ),
              iOS: DarwinNotificationDetails(),
            ),
            payload: payload,
          );
    }
  });

  FirebaseMessaging.onMessageOpenedApp.listen(notificationNavigator.handleMessage);

  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      unawaited(notificationNavigator.handleMessage(initialMessage));
    });
  }

  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user != null) {
      final token = await messaging.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({'fcmToken': token}, SetOptions(merge: true));
      }
    }
  });
}

class MyApp extends StatelessWidget {
  final bool appCheckFailed;
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  final FirebaseMessaging? messaging;

  const MyApp({
    super.key,
    required this.appCheckFailed,
    this.firestore,
    this.auth,
    this.messaging,
  });

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    // Force specific seed color (Purple/Expressive) regardless of system/wallpaper
    final lightScheme = AppTheme.seededColorScheme(Brightness.light);
    final darkScheme = AppTheme.seededColorScheme(Brightness.dark);

    return MaterialApp(
      title: 'Bible Reading Challenge',
      theme: AppTheme.appTheme(lightScheme),
      darkTheme: AppTheme.appTheme(darkScheme),
      themeMode: ThemeMode.system,
      navigatorKey: _rootNavigatorKey,
      home: MainPage(
        appCheckFailed: appCheckFailed,
        firestore: firestore,
        auth: auth,
        messaging: messaging,
      ),
    );
  }
}

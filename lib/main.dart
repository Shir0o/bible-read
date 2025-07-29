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
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Log whether the app is running in debug mode.
  debugPrint('kDebugMode: $kDebugMode');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
  // Wait for FirebaseAuth to be ready before activating App Check.
  await FirebaseAuth.instance.authStateChanges().first;
  bool appCheckFailed = false;
  try {
    if (kDebugMode) {
      await FirebaseAppCheck.instance.activate(
        androidProvider: AndroidProvider.debug,
        appleProvider: AppleProvider.debug,
      );
    } else {
      await FirebaseAppCheck.instance.activate(
        androidProvider: AndroidProvider.playIntegrity,
        appleProvider: AppleProvider.appAttest,
      );
    }
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('AppCheck activation failed: $e\n$st');
    }
    ErrorLogger.log(e, st);

    try {
      await FirebaseFirestore.instance.collection('app_check_errors').add({
        'timestamp': Timestamp.now(),
        'error': e.toString(),
        'stack': st.toString(),
        'platform': defaultTargetPlatform.toString(),
      });
    } catch (firestoreError, st) {
      if (kDebugMode) {
        debugPrint(
            'Failed to log AppCheck error to Firestore: $firestoreError');
      }
      ErrorLogger.log(firestoreError, st);
    }
    appCheckFailed = true;
  }
  await _setupMessaging();
  runApp(MyApp(appCheckFailed: appCheckFailed));
}

final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _setupMessaging() async {
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission();

  const initializationSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );
  await _localNotificationsPlugin.initialize(initializationSettings);

  FirebaseMessaging.onMessage.listen((message) async {
    final notification = message.notification;
    if (notification != null) {
      await _localNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'default_channel',
            'Notifications',
            importance: Importance.defaultImportance,
          ),
        ),
      );
    }
  });

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

  const MyApp({super.key, required this.appCheckFailed});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bible Reading Challenge',
      theme: AppTheme.appTheme,
      home: MainPage(appCheckFailed: appCheckFailed),
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:bible_read/pages/friend_invite_page.dart';
import 'package:bible_read/pages/group_join_requests_page.dart';
import 'package:bible_read/pages/join_by_code_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/services/friend_invite.dart';
import 'package:bible_read/services/join_code_service.dart';
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
import 'services/google_sign_in_factory.dart';
import 'services/reminder_service.dart';
import 'services/group_service.dart';
import 'theme/app_theme.dart';

// Global flag to skip messaging setup, useful for integration tests to avoid
// system permission dialogs that block the UI.
bool skipMessagingSetup = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Log whether the app is running in debug mode.
  debugPrint('kDebugMode: $kDebugMode');

  // Android's FirebaseInitProvider initializes [DEFAULT] natively before Dart
  // runs. firebase_core then throws [core/duplicate-app]; catch it
  // and fall back to the existing native app.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
  bool appCheckFailed = false;
  try {
    if (kDebugMode) {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: AndroidDebugProvider(),
        providerApple: AppleDebugProvider(),
      );
      // Try to get token to trigger debug token print in logs
      try {
        final token = await FirebaseAppCheck.instance.getToken();
        debugPrint('Firebase App Check debug token: $token');
      } catch (e) {
        debugPrint('AppCheck getToken failed (normal for simulators): $e');
        debugPrint(
          'TIP: If using an emulator, you may need to add a Debug Token in the Firebase Console under App Check.',
        );
      }
    } else {
      await FirebaseAppCheck.instance
          .activate(
            providerAndroid: AndroidPlayIntegrityProvider(),
            providerApple: AppleAppAttestProvider(),
          )
          .timeout(const Duration(seconds: 4));
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
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
    !kDebugMode,
  );

  unawaited(
    initializeGoogleSignIn().catchError((Object error, StackTrace st) {
      if (kDebugMode) {
        debugPrint('Google Sign-In init failed: $error');
      }
      ErrorLogger.log(error, st);
    }),
  );

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
    unawaited(
      _setupMessaging().catchError((Object error, StackTrace st) {
        if (kDebugMode) {
          debugPrint('Messaging setup failed: $error');
        }
        ErrorLogger.log(error, st);
      }),
    );
    unawaited(
      _setupIncomingLinks().catchError((Object error, StackTrace st) {
        if (kDebugMode) {
          debugPrint('Incoming link setup failed: $error');
        }
        ErrorLogger.log(error, st);
      }),
    );
  }
  runApp(MyApp(appCheckFailed: appCheckFailed));
}

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

class NotificationNavigator {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  NotificationNavigator({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : auth = auth ?? FirebaseAuth.instance,
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
      case 'friend':
        // Show the Circle tab on the existing shell rather than pushing a
        // second MainPage over the first.
        navigator.popUntil((route) => route.isFirst);
        MainPage.requestedTab.value = MainPage.circleTabIndex;
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

/// Routes an incoming invite link to the appropriate confirm screen. An
/// eight-character friend code opens [FriendInvitePage], while a six-character
/// group code opens [JoinByCodePage]. A link that arrives while signed out,
/// or before the navigator is ready, is held until sign-in so the invite is
/// not lost.
class IncomingLinkHandler {
  final FirebaseAuth auth;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget Function(String code) pageBuilder;

  String? _pendingCode;

  IncomingLinkHandler({
    FirebaseAuth? auth,
    GlobalKey<NavigatorState>? navigatorKey,
    Widget Function(String code)? pageBuilder,
  })  : auth = auth ?? FirebaseAuth.instance,
        navigatorKey = navigatorKey ?? _rootNavigatorKey,
        pageBuilder = pageBuilder ?? _defaultInvitePage;

  static Widget _defaultInvitePage(String code) {
    if (code.length == JoinCodeService.codeLength) {
      return JoinByCodePage(initialCode: code);
    }
    return FriendInvitePage(code: code);
  }

  /// Reads an invite out of [uri] and opens the confirm screen, or holds it
  /// until the reader is signed in.
  Future<void> handleUri(Uri uri) async {
    final code = FriendInvite.codeFrom(uri);
    if (code == null) return;
    if (auth.currentUser == null) {
      _pendingCode = code;
      return;
    }
    _show(code);
  }

  /// Shows a held invite once a reader has signed in.
  void onSignedIn() {
    final code = _pendingCode;
    if (code == null) return;
    _pendingCode = null;
    _show(code);
  }

  void _show(String code) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _pendingCode = code;
      return;
    }
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => pageBuilder(code)),
      ),
    );
  }
}

// Global instance for convenience, can be overridden in tests.
IncomingLinkHandler incomingLinkHandler = IncomingLinkHandler();

Future<void> _setupIncomingLinks() async {
  // Drain a held invite when the reader signs in (story 4).
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) incomingLinkHandler.onSignedIn();
  });

  // The stream replays links received before the first listen, including a
  // cold-start link, so one subscription covers every case.
  AppLinks().uriLinkStream.listen(
        (uri) => unawaited(incomingLinkHandler.handleUri(uri)),
        onError: (Object e, StackTrace st) => unawaited(ErrorLogger.log(e, st)),
      );
}

Future<void> _setupMessaging() async {
  final messaging = FirebaseMessaging.instance;
  unawaited(
    messaging.requestPermission().catchError((e) {
      if (kDebugMode) {
        debugPrint('Permission request failed: $e');
      }
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
    }),
  );

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
            id: notification.hashCode,
            title: notification.title,
            body: notification.body,
            notificationDetails: const NotificationDetails(
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

  FirebaseMessaging.onMessageOpenedApp.listen(
    notificationNavigator.handleMessage,
  );

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
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'fcmToken': token,
        }, SetOptions(merge: true));
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
    // Use the Bible Read design palette (warm paper / deep aubergine), ignoring
    // system/wallpaper dynamic color.
    const lightScheme = AppTheme.designLightScheme;
    const darkScheme = AppTheme.designDarkScheme;

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

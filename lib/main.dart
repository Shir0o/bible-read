import 'package:bible_read/pages/main_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await _setupMessaging();
  runApp(const MyApp());
}

final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _setupMessaging() async {
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission();

  const initializationSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
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
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bible Reading Challenge',
      theme: ThemeData(
        brightness: Brightness.dark,
        // This is the theme of your application.
        // It uses Material 3 with a purple seed color.
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo.shade900, brightness: Brightness.dark),
        useMaterial3: true,
        fontFamily: 'IBMPlexMono',
      ),
      home: MainPage(),
    );
  }
}

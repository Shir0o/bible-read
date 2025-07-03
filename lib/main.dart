import 'package:bible_read/pages/main_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo.shade900, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const MainPage(),
    );
  }
}

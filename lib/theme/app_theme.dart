import 'package:flutter/material.dart';

class AppTheme {
  static const String fontFamily = 'IBMPlexMono';

  static final ColorScheme colorScheme = ColorScheme.fromSeed(
    seedColor: Colors.indigo.shade900,
    brightness: Brightness.dark,
  );

  static final TextTheme textTheme = TextTheme(
    bodyLarge: const TextStyle(fontSize: 16, fontFamily: fontFamily),
    bodyMedium: const TextStyle(fontSize: 14, fontFamily: fontFamily),
    titleMedium: const TextStyle(
        fontSize: 18, fontFamily: fontFamily, fontWeight: FontWeight.bold),
  );

  static final ThemeData appTheme = ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    useMaterial3: true,
    fontFamily: fontFamily,
    textTheme: textTheme,
  );
}

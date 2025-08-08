import 'package:flutter/material.dart';

class AppTheme {
  static const String fontFamily = 'IBMPlexMono';
  static const Color backgroundColor = Colors.black;

  static const RoundedRectangleBorder _buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)));

  static const EdgeInsetsGeometry _buttonPadding =
      EdgeInsets.symmetric(horizontal: 16, vertical: 12);

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

  static final ButtonStyle _baseButtonStyle = ButtonStyle(
    animationDuration: const Duration(milliseconds: 200),
    overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed) ||
          states.contains(WidgetState.hovered)) {
        return colorScheme.primary.withValues(alpha: 0.1);
      }
      return null;
    }),
    shape: WidgetStateProperty.all<OutlinedBorder>(_buttonShape),
    padding: WidgetStateProperty.all<EdgeInsetsGeometry>(_buttonPadding),
  );

  static final ButtonStyle _elevatedButtonStyle = _baseButtonStyle.copyWith(
    elevation: WidgetStateProperty.resolveWith<double?>((states) {
      if (states.contains(WidgetState.pressed)) {
        return 6;
      }
      return 2;
    }),
  );

  static final ThemeData appTheme = ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    useMaterial3: true,
    fontFamily: fontFamily,
    textTheme: textTheme,
    scaffoldBackgroundColor: backgroundColor,
    appBarTheme: const AppBarTheme(backgroundColor: backgroundColor),
    elevatedButtonTheme: ElevatedButtonThemeData(style: _elevatedButtonStyle),
    textButtonTheme: TextButtonThemeData(style: _baseButtonStyle),
  );
}

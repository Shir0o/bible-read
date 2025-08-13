// Defines the global color scheme, fonts, and button styles.
import 'package:flutter/material.dart';

/// Provides the application's theme configuration.
///
/// Update [colorScheme] to change primary colors and adjust [fontFamily] or
/// [textTheme] to modify typography.
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

  /// Base configuration for text and elevated buttons.
  ///
  /// Modify shape, padding, or overlay color to customize button appearance.
  static final ButtonStyle _baseButtonStyle = ButtonStyle(
    animationDuration: const Duration(milliseconds: 200),
    overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed) ||
          states.contains(WidgetState.hovered)) {
        return colorScheme.primary.withAlpha((0.1 * 255).round());
      }
      return null;
    }),
    shape: WidgetStateProperty.all<OutlinedBorder>(_buttonShape),
    padding: WidgetStateProperty.all<EdgeInsetsGeometry>(_buttonPadding),
  );

  /// Elevated button variant of [_baseButtonStyle].
  ///
  /// Tweak the elevation values to alter the raised effect.
  static final ButtonStyle _elevatedButtonStyle = _baseButtonStyle.copyWith(
    elevation: WidgetStateProperty.resolveWith<double?>((states) {
      if (states.contains(WidgetState.pressed)) {
        return 6;
      }
      return 2;
    }),
  );

  /// Complete [ThemeData] for the application.
  ///
  /// Adjust [colorScheme], [textTheme], or button themes to change the overall
  /// look and feel.
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

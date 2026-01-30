// Defines the global color scheme, fonts, spacing, and button styles.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Provides the application's theme configuration.
///
/// Pass a [ColorScheme] to [appTheme] to change primary colors and adjust
/// [fontFamily] or [textTheme] to modify typography.
class AppTheme {
  static TextTheme _applyIBMFont(TextTheme base) =>
      GoogleFonts.ibmPlexSansTextTheme(base);

  static Typography _buildTypography() {
    final materialTypography = Typography.material2021();

    return materialTypography.copyWith(
      black: _applyIBMFont(materialTypography.black),
      white: _applyIBMFont(materialTypography.white),
    );
  }

  static final Typography typography = _buildTypography();
  static final TextTheme textTheme = typography.black;
  static final TextTheme primaryTextTheme = typography.white;

  // Material 3 Ref Palette Colors
  static const Color neutral90 = Color(0xFFE6E0E9);
  static const Color neutral22 = Color(0xFF36343B);
  static const Color neutralVariant30 = Color(0xFF49454F);
  static const Color primary90 = Color(0xFFEADDFF);
  static const Color primary30 = Color(0xFF4F378B);

  /// Generates a seeded [ColorScheme] to use when dynamic colors are
  /// unavailable.
  static ColorScheme seededColorScheme(Brightness brightness) =>
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4), // M3 Purple
        brightness: brightness,
      );

  /// Complete [ThemeData] for the application.
  ///
  /// Adjust [colorScheme], [textTheme], or button themes to change the overall
  /// look and feel.
  static ThemeData appTheme(ColorScheme colorScheme) {
    // Apply standard M3 typography scaling
    final themedText = (colorScheme.brightness == Brightness.light
            ? textTheme
            : primaryTextTheme)
        .copyWith(
          bodyMedium: GoogleFonts.ibmPlexSans(fontSize: 16),
        )
        .apply(
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
        );

    return ThemeData(
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      useMaterial3: true,
      textTheme: themedText,
      primaryTextTheme: primaryTextTheme,
      typography: typography,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        titleTextStyle:
            themedText.titleLarge?.copyWith(color: colorScheme.onSurface),
        elevation: 0,
        centerTitle: false,
      ),
    );
  }
}

/// Spacing scale for consistent layout paddings and gaps.
class AppSpacing {
  static const double unit = 8;
  static const double hPadding = 16;
  static const double vPadding = 16;
  static const double vPaddingSmall = 8;

  static const EdgeInsets screen =
      EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding);
  static const EdgeInsets horizontal =
      EdgeInsets.symmetric(horizontal: hPadding);
  static const EdgeInsets list = EdgeInsets.symmetric(
    horizontal: hPadding,
    vertical: vPaddingSmall,
  );
}

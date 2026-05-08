// Defines the global color scheme, fonts, spacing, and button styles.
import 'package:flutter/material.dart';

/// Provides the application's theme configuration.
///
/// Pass a [ColorScheme] to [appTheme] to change primary colors and adjust
/// [fontFamily] or [textTheme] to modify typography.
class AppTheme {
  static const String authHeroImageUrl =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuCfzrtAkMN22RwB2ZiqvZ7-a-u3c-1Q3SYe1V6xrgX8oGAGl0fcdKTFGezJhbpHXu8o1n3ePffi_ZF79ajNqZfUsXddI-13tqUsvWaaiNgLKefDYXK0KgRmpDPKA_meuN2OR1SNZqMAEjz6CXvzG7W7A6V3Do9bc_HOxoFH-5RLqbVZek6jTgqM-ERrpHdie1ASqWaBbJxXCKiQDVcL0TkaFmAp07o9oaHvgLprritLLT8kmwNubpE4Xl6s2ETlB0C7b6HWAgBESSe6';

  /// App-wide Google Sans typography entry point.
  ///
  /// Google Sans is not available through `google_fonts`, so this uses Roboto,
  /// Google's public Material font, without runtime font fetching.
  static TextStyle googleSans({
    TextStyle? textStyle,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    TextBaseline? textBaseline,
    double? height,
    Locale? locale,
    Paint? foreground,
    Paint? background,
    List<Shadow>? shadows,
    List<FontFeature>? fontFeatures,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
  }) {
    final base = textStyle ?? const TextStyle();
    return base.copyWith(
      fontFamily: 'Roboto',
      color: color,
      backgroundColor: backgroundColor,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      textBaseline: textBaseline,
      height: height,
      locale: locale,
      foreground: foreground,
      background: background,
      shadows: shadows,
      fontFeatures: fontFeatures,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
    );
  }

  /// Applies the app's Google Sans typography to a text theme.
  static TextTheme googleSansTextTheme([TextTheme? base]) {
    final textTheme = base ?? Typography.material2021().black;
    return textTheme.copyWith(
      displayLarge: googleSans(textStyle: textTheme.displayLarge),
      displayMedium: googleSans(textStyle: textTheme.displayMedium),
      displaySmall: googleSans(textStyle: textTheme.displaySmall),
      headlineLarge: googleSans(textStyle: textTheme.headlineLarge),
      headlineMedium: googleSans(textStyle: textTheme.headlineMedium),
      headlineSmall: googleSans(textStyle: textTheme.headlineSmall),
      titleLarge: googleSans(textStyle: textTheme.titleLarge),
      titleMedium: googleSans(textStyle: textTheme.titleMedium),
      titleSmall: googleSans(textStyle: textTheme.titleSmall),
      bodyLarge: googleSans(textStyle: textTheme.bodyLarge),
      bodyMedium: googleSans(textStyle: textTheme.bodyMedium),
      bodySmall: googleSans(textStyle: textTheme.bodySmall),
      labelLarge: googleSans(textStyle: textTheme.labelLarge),
      labelMedium: googleSans(textStyle: textTheme.labelMedium),
      labelSmall: googleSans(textStyle: textTheme.labelSmall),
    );
  }

  static TextTheme _applyFont(TextTheme base) => googleSansTextTheme(base);

  static Color successColor(ColorScheme colorScheme) => colorScheme.tertiary;

  static Color onSuccessColor(ColorScheme colorScheme) =>
      colorScheme.onTertiary;

  static Typography _buildTypography() {
    final materialTypography = Typography.material2021();

    return materialTypography.copyWith(
      black: _applyFont(materialTypography.black),
      white: _applyFont(materialTypography.white),
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

  // Material 3 Dark Colors
  static const Color m3DarkSurface = Color(0xFF141218);
  static const Color m3Primary = Color(0xFFD0BCFF);
  static const Color m3OnPrimary = Color(0xFF381E72);
  static const Color m3SurfaceDim = Color(0xFFDED8E1);
  static const Color m3SurfaceBright = Color(0xFFFEF7FF);

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
    final isLight = colorScheme.brightness == Brightness.light;
    final baseTextTheme = isLight ? textTheme : primaryTextTheme;

    // Apply standard M3 typography scaling and custom overrides
    final themedText = _applyFont(baseTextTheme).copyWith(
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: 16,
        color: colorScheme.onSurface,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: 14,
        color: colorScheme.onSurfaceVariant,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: colorScheme.onSurfaceVariant,
      ),
    );

    return ThemeData(
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      useMaterial3: true,
      textTheme: themedText,
      primaryTextTheme: primaryTextTheme,
      typography: typography,
      scaffoldBackgroundColor: colorScheme.surface,
      shadowColor: isLight ? Colors.black : Colors.black.withValues(alpha: 0.5),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: themedText.titleLarge,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.hPadding,
          vertical: AppSpacing.vPaddingSmall,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return themedText.labelMedium?.copyWith(
            color: selected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
        selectedIconTheme:
            IconThemeData(color: colorScheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        selectedLabelTextStyle: themedText.labelMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: themedText.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
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

  /// Standard card shadow
  static List<BoxShadow> cardShadow(BuildContext context) {
    final theme = Theme.of(context);
    return [
      BoxShadow(
        color: theme.shadowColor.withValues(alpha: 0.1),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ];
  }
}

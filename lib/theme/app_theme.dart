// Defines the global color scheme, fonts, spacing, and button styles.
//
// The visual system follows the Bible Read design: a warm-paper light mode and
// a deep-aubergine night mode, with a lavender primary and a warm-gold accent.
// Typography pairs Spectral (serif — headings, scripture, section titles) with
// Hanken Grotesk (sans — body, UI, buttons, labels). Both fonts are bundled as
// assets (see pubspec.yaml); no runtime font fetching is required.
import 'package:flutter/material.dart';

/// Provides the application's theme configuration.
///
/// Pass a [ColorScheme] to [appTheme] to change primary colors and adjust
/// [fontFamily] or [textTheme] to modify typography.
class AppTheme {
  static const String authHeroImageUrl =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuCfzrtAkMN22RwB2ZiqvZ7-a-u3c-1Q3SYe1V6xrgX8oGAGl0fcdKTFGezJhbpHXu8o1n3ePffi_ZF79ajNqZfUsXddI-13tqUsvWaaiNgLKefDYXK0KgRmpDPKA_meuN2OR1SNZqMAEjz6CXvzG7W7A6V3Do9bc_HOxoFH-5RLqbVZek6jTgqM-ERrpHdie1ASqWaBbJxXCKiQDVcL0TkaFmAp07o9oaHvgLprritLLT8kmwNubpE4Xl6s2ETlB0C7b6HWAgBESSe6';

  /// Serif family — headings, scripture, section titles.
  static const String fontSerif = 'Spectral';

  /// Sans family — body copy, UI chrome, buttons, labels.
  static const String fontUi = 'Hanken Grotesk';

  /// Applies the app's UI (sans) typography to a text theme.
  static TextTheme uiTextTheme([TextTheme? base]) =>
      (base ?? Typography.material2021().black).apply(fontFamily: fontUi);

  static TextTheme _applyFont(TextTheme base) => uiTextTheme(base);

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

  // ---------------------------------------------------------------------------
  // Design color schemes (from app/theme.jsx in the design bundle).
  // Surface containers are mapped so `surfaceContainerLowest` is the card
  // surface in *both* modes (brightest paper in light, raised panel in dark).
  // ---------------------------------------------------------------------------

  /// Warm-paper light mode.
  static const ColorScheme designLightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF6A53AD), // --primary
    onPrimary: Color(0xFFFFFFFF), // --on-primary
    primaryContainer: Color(0xFFEDE9F5), // --primary-soft (solid tint)
    onPrimaryContainer: Color(0xFF5B449E), // --primary-press
    secondary: Color(0xFF6A53AD),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFEDE9F5),
    onSecondaryContainer: Color(0xFF5B449E),
    tertiary: Color(0xFFBE8A52), // --accent (warm gold)
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFF3E8D9),
    onTertiaryContainer: Color(0xFF6E4D20),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF410E0B),
    surface: Color(0xFFF4F0E8), // --bg
    onSurface: Color(0xFF231E2C), // --text
    onSurfaceVariant: Color(0xFF6C6577), // --text-dim
    surfaceContainerLowest: Color(0xFFFFFDFA), // --surface (cards)
    surfaceContainerLow: Color(0xFFF5F1E9), // --surface-2
    surfaceContainer: Color(0xFFEFEAE0),
    surfaceContainerHigh: Color(0xFFE9E2D5), // --surface-3
    surfaceContainerHighest: Color(0xFFE3DBCC),
    surfaceDim: Color(0xFFDDD6C9),
    surfaceBright: Color(0xFFFBF8F2),
    outline: Color(0xFFA8A0AC), // --text-faint
    outlineVariant: Color(0xFFDCD6DF), // --border (light)
    inverseSurface: Color(0xFF322C3B),
    onInverseSurface: Color(0xFFF4EFF6),
    inversePrimary: Color(0xFFC6B4EC),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Color(0xFF6A53AD),
  );

  /// Deep-aubergine night mode.
  static const ColorScheme designDarkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFC6B4EC), // --primary (dark)
    onPrimary: Color(0xFF22153D), // --on-primary (dark)
    primaryContainer: Color(0xFF3A2D55),
    onPrimaryContainer: Color(0xFFE5DCF7),
    secondary: Color(0xFFC6B4EC),
    onSecondary: Color(0xFF22153D),
    secondaryContainer: Color(0xFF2E2640),
    onSecondaryContainer: Color(0xFFE5DCF7),
    tertiary: Color(0xFFE1B488), // --accent (dark)
    onTertiary: Color(0xFF3A2410),
    tertiaryContainer: Color(0xFF4D3620),
    onTertiaryContainer: Color(0xFFF5E0CC),
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFF9DEDC),
    surface: Color(0xFF16121D), // --bg (dark)
    onSurface: Color(0xFFECE7F3), // --text (dark)
    onSurfaceVariant: Color(0xFFA39CB3), // --text-dim (dark)
    surfaceContainerLowest: Color(0xFF1E1926), // --surface (cards)
    surfaceContainerLow: Color(0xFF272030), // --surface-2
    surfaceContainer: Color(0xFF2A2333),
    surfaceContainerHigh: Color(0xFF332B3E), // --surface-3
    surfaceContainerHighest: Color(0xFF3C3447),
    surfaceDim: Color(0xFF16121D),
    surfaceBright: Color(0xFF3C3447),
    outline: Color(0xFF6E6781), // --text-faint (dark)
    outlineVariant: Color(0xFF353040), // --border (dark)
    inverseSurface: Color(0xFFECE7F3),
    onInverseSurface: Color(0xFF322C3B),
    inversePrimary: Color(0xFF6A53AD),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Color(0xFFC6B4EC),
  );

  /// Generates a seeded [ColorScheme] to use when dynamic colors are
  /// unavailable. Retained for callers that need a derived scheme; the app
  /// itself uses [designLightScheme] / [designDarkScheme].
  static ColorScheme seededColorScheme(Brightness brightness) =>
      brightness == Brightness.dark ? designDarkScheme : designLightScheme;

  /// Complete [ThemeData] for the application.
  ///
  /// Adjust [colorScheme], [textTheme], or button themes to change the overall
  /// look and feel.
  static ThemeData appTheme(ColorScheme colorScheme) {
    final isLight = colorScheme.brightness == Brightness.light;
    final baseTextTheme = isLight ? textTheme : primaryTextTheme;
    final onSurface = colorScheme.onSurface;
    final onVariant = colorScheme.onSurfaceVariant;

    // Apply the design type scale on top of the sans (Hanken) base. Display /
    // headline / title-large slots switch to the Spectral serif; the remaining
    // body / label slots stay sans.
    final themedText = _applyFont(baseTextTheme).copyWith(
      displaySmall: TextStyle(
        fontFamily: fontSerif,
        fontSize: 32,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.5,
        height: 1.15,
        color: onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: fontSerif,
        fontSize: 26,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.4,
        color: onSurface,
      ),
      headlineSmall: TextStyle(
        fontFamily: fontSerif,
        fontSize: 24,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.3,
        color: onSurface,
      ),
      // Section titles: Spectral 19 / 500 / -0.01em.
      titleLarge: TextStyle(
        fontFamily: fontSerif,
        fontSize: 19,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
        color: onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: fontUi,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      titleSmall: TextStyle(
        fontFamily: fontUi,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      bodyLarge: TextStyle(
        fontFamily: fontUi,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: onSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: fontUi,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: onVariant,
      ),
      bodySmall: TextStyle(
        fontFamily: fontUi,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: onVariant,
      ),
      // Button text: Hanken 15 / 600.
      labelLarge: TextStyle(
        fontFamily: fontUi,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      // Chips / tabs: Hanken 12.5 / 600.
      labelMedium: TextStyle(
        fontFamily: fontUi,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: onVariant,
      ),
      // Eyebrow: Hanken 11 / 700 / 0.16em (uppercase applied at usage).
      labelSmall: TextStyle(
        fontFamily: fontUi,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
        color: onVariant,
      ),
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.rButton),
    );
    final buttonTextStyle = themedText.labelLarge;
    // Enforce the design's 52px height without forcing width: a 0 min-width
    // keeps buttons intrinsically sized (and full-width only when their parent
    // constrains them), avoiding infinite-width layout errors.
    const buttonSize = Size(0, AppSpacing.buttonHeight);

    return ThemeData(
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: fontUi,
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
        color: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.hPadding,
          vertical: AppSpacing.vPaddingSmall,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.rCard),
          side: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: buttonTextStyle,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: buttonTextStyle,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: buttonTextStyle,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: buttonShape,
          textStyle: buttonTextStyle,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.rField),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.rField),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.rField),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.rField),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.rField),
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
        selectedIconTheme: IconThemeData(
          color: colorScheme.onSecondaryContainer,
        ),
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
  static const double hPadding = 20;
  static const double vPadding = 16;
  static const double vPaddingSmall = 8;

  // Gap scale.
  static const double gap4 = 4;
  static const double gap8 = 8;
  static const double gap12 = 12;
  static const double gap16 = 16;
  static const double gap20 = 20;
  static const double gap24 = 24;

  // Corner radii (from the design).
  static const double rCard = 22;
  static const double rButton = 16;
  static const double rField = 16;
  static const double rInset = 16;
  static const double rChip = 12;
  static const double rSheet = 26;

  // Component metrics.
  static const double buttonHeight = 52;

  static const EdgeInsets screen = EdgeInsets.symmetric(
    horizontal: hPadding,
    vertical: vPadding,
  );
  static const EdgeInsets horizontal = EdgeInsets.symmetric(
    horizontal: hPadding,
  );
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

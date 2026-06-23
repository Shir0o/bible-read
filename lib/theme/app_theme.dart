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
    primaryContainer: Color(0xFFF0ECF2), // --primary-soft flattened over --surface
    onPrimaryContainer: Color(0xFF5B449E), // --primary-press
    secondary: Color(0xFF6A53AD),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF0ECF2), // --primary-soft flattened
    onSecondaryContainer: Color(0xFF5B449E),
    tertiary: Color(0xFFA0702F), // --accent (warm gold, solid)
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFF6EDE3), // --accent-soft flattened
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
    outline: Color(0xFF8C8694), // --text-faint
    outlineVariant: Color(0xFFEDEAEA), // --border flattened over --surface
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
    primaryContainer: Color(0xFF342D40), // --primary-soft flattened over --surface
    onPrimaryContainer: Color(0xFFE5DCF7),
    secondary: Color(0xFFC6B4EC),
    onSecondary: Color(0xFF22153D),
    secondaryContainer: Color(0xFF342D40), // --primary-soft flattened
    onSecondaryContainer: Color(0xFFE5DCF7),
    tertiary: Color(0xFFE1B488), // --accent (dark)
    onTertiary: Color(0xFF3A2410),
    tertiaryContainer: Color(0xFF3D3236), // --accent-soft flattened
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
    outlineVariant: Color(0xFF2F2A36), // --border flattened over --surface (dark)
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
    final appColors = isLight ? AppColors.light : AppColors.dark;

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
      extensions: <ThemeExtension<dynamic>>[
        isLight ? AppColors.light : AppColors.dark,
      ],
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
          side: BorderSide(color: appColors.border, width: 1),
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

/// Design tokens that don't map cleanly onto Material's [ColorScheme] — the
/// translucent overlay/border colors and a few solids from `app/theme.jsx`.
///
/// These keep their alpha so they blend correctly over whatever surface they
/// land on (a card, the page background, a sheet), which is why they live here
/// rather than being flattened into [ColorScheme]. Access via
/// `AppColors.of(context)`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primarySoft,
    required this.primaryLine,
    required this.primaryPress,
    required this.accentSoft,
    required this.border,
    required this.borderStrong,
    required this.highlight,
    required this.bg2,
    required this.scrim,
  });

  /// Soft primary fill — `--primary-soft`. Selected/active chip & pill grounds.
  final Color primarySoft;

  /// Translucent primary hairline — `--primary-line`. Selected/outlined borders.
  final Color primaryLine;

  /// Solid pressed-primary — `--primary-press`.
  final Color primaryPress;

  /// Soft warm-accent fill — `--accent-soft`.
  final Color accentSoft;

  /// Generic translucent border — `--border`. Card hairlines, dividers.
  final Color border;

  /// Emphasized translucent border — `--border-strong`.
  final Color borderStrong;

  /// Scripture/text highlight — `--hl`. (No consumer yet; defined for parity.)
  final Color highlight;

  /// Recessed background — `--bg-2`.
  final Color bg2;

  /// Modal barrier scrim — design `rgba(10,8,14,0.42)`, same in both modes.
  final Color scrim;

  static const Color _scrim = Color.fromRGBO(10, 8, 14, 0.42);

  /// Warm-paper light mode tokens.
  static const AppColors light = AppColors(
    primarySoft: Color.fromRGBO(106, 83, 173, 0.10),
    primaryLine: Color.fromRGBO(106, 83, 173, 0.26),
    primaryPress: Color(0xFF5B449E),
    accentSoft: Color.fromRGBO(190, 138, 82, 0.14),
    border: Color.fromRGBO(43, 33, 58, 0.085),
    borderStrong: Color.fromRGBO(43, 33, 58, 0.15),
    highlight: Color.fromRGBO(190, 138, 82, 0.20),
    bg2: Color(0xFFEDE7DC),
    scrim: _scrim,
  );

  /// Deep-aubergine night mode tokens.
  static const AppColors dark = AppColors(
    primarySoft: Color.fromRGBO(198, 180, 236, 0.13),
    primaryLine: Color.fromRGBO(198, 180, 236, 0.30),
    primaryPress: Color(0xFFB6A1E6),
    accentSoft: Color.fromRGBO(225, 180, 136, 0.16),
    border: Color.fromRGBO(255, 255, 255, 0.075),
    borderStrong: Color.fromRGBO(255, 255, 255, 0.14),
    highlight: Color.fromRGBO(225, 180, 136, 0.22),
    bg2: Color(0xFF110E17),
    scrim: _scrim,
  );

  /// The [AppColors] for the current theme. Falls back to the brightness-
  /// appropriate token set if the extension isn't registered (e.g. a widget
  /// rendered under a bare [MaterialApp] in a test or preview).
  static AppColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  AppColors copyWith({
    Color? primarySoft,
    Color? primaryLine,
    Color? primaryPress,
    Color? accentSoft,
    Color? border,
    Color? borderStrong,
    Color? highlight,
    Color? bg2,
    Color? scrim,
  }) {
    return AppColors(
      primarySoft: primarySoft ?? this.primarySoft,
      primaryLine: primaryLine ?? this.primaryLine,
      primaryPress: primaryPress ?? this.primaryPress,
      accentSoft: accentSoft ?? this.accentSoft,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      highlight: highlight ?? this.highlight,
      bg2: bg2 ?? this.bg2,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      primaryLine: Color.lerp(primaryLine, other.primaryLine, t)!,
      primaryPress: Color.lerp(primaryPress, other.primaryPress, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      bg2: Color.lerp(bg2, other.bg2, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
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

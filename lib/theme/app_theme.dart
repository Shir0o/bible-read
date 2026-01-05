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

  static const RoundedRectangleBorder _buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)));

  static const EdgeInsetsGeometry _buttonPadding =
      EdgeInsets.symmetric(horizontal: 16, vertical: 12);

  static WidgetStateColor stateLayer(Color baseColor) =>
      WidgetStateColor.resolveWith((states) {
        const hoveredOpacity = 0.08;
        const focusedOpacity = 0.12;
        const pressedOpacity = 0.12;
        const draggedOpacity = 0.16;

        if (states.contains(WidgetState.pressed)) {
          return baseColor.withValues(alpha: pressedOpacity);
        }
        if (states.contains(WidgetState.dragged)) {
          return baseColor.withValues(alpha: draggedOpacity);
        }
        if (states.contains(WidgetState.hovered)) {
          return baseColor.withValues(alpha: hoveredOpacity);
        }
        if (states.contains(WidgetState.focused)) {
          return baseColor.withValues(alpha: focusedOpacity);
        }
        return Colors.transparent;
      });

  /// Generates a seeded [ColorScheme] to use when dynamic colors are
  /// unavailable.
  static ColorScheme seededColorScheme(Brightness brightness) =>
      ColorScheme.fromSeed(
        seedColor: Colors.indigo.shade900,
        brightness: brightness,
      );

  /// Base configuration for text and elevated buttons.
  ///
  /// Modify shape, padding, or overlay color to customize button appearance.
  static ButtonStyle _baseButtonStyle(ColorScheme colorScheme) => ButtonStyle(
        animationDuration: const Duration(milliseconds: 180),
        overlayColor: stateLayer(colorScheme.surfaceTint),
        shape: WidgetStateProperty.all<OutlinedBorder>(_buttonShape),
        padding: WidgetStateProperty.all<EdgeInsetsGeometry>(_buttonPadding),
      );

  /// Elevated button variant of [_baseButtonStyle].
  ///
  /// Tweak the elevation values to alter the raised effect.
  static ButtonStyle _elevatedButtonStyle(ColorScheme colorScheme) =>
      _baseButtonStyle(colorScheme).copyWith(
        elevation: WidgetStateProperty.resolveWith<double?>((states) {
          if (states.contains(WidgetState.pressed)) {
            return 6;
          }
          return 2;
        }),
        overlayColor: stateLayer(colorScheme.surfaceTint),
      );

  /// Outlined button variant aligned with base style.
  static ButtonStyle _outlinedButtonStyle(ColorScheme colorScheme) =>
      _baseButtonStyle(colorScheme).copyWith(
        side: WidgetStateProperty.all(
          BorderSide(color: colorScheme.outlineVariant),
        ),
      );

  /// Filled button variant tuned for Material 3 visual language.
  static ButtonStyle _filledButtonStyle(ColorScheme colorScheme) =>
      _baseButtonStyle(colorScheme).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.pressed)) {
            return colorScheme.primaryContainer;
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return colorScheme.primaryFixedDim;
          }
          return colorScheme.primary;
        }),
        foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.pressed)) {
            return colorScheme.onPrimaryContainer;
          }
          return colorScheme.onPrimary;
        }),
        shadowColor: WidgetStateProperty.all(colorScheme.surfaceTint),
        surfaceTintColor: WidgetStateProperty.all(colorScheme.primary),
        elevation: WidgetStateProperty.resolveWith<double?>((states) {
          if (states.contains(WidgetState.disabled)) return 0;
          if (states.contains(WidgetState.pressed)) return 1.5;
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return 4.5;
          }
          return 3;
        }),
      );

  /// Complete [ThemeData] for the application.
  ///
  /// Adjust [colorScheme], [textTheme], or button themes to change the overall
  /// look and feel.
  static ThemeData appTheme(ColorScheme colorScheme) {
    // Override colors to ensure text is strictly black
    final blackColorScheme = colorScheme.copyWith(
      onSurface: Colors.black,
      onSurfaceVariant: Colors.black,
    );

    final themedText = (blackColorScheme.brightness == Brightness.light
            ? textTheme
            : primaryTextTheme)
        .copyWith(
          bodyMedium: GoogleFonts.ibmPlexSans(fontSize: 16),
        )
        .apply(
          bodyColor: Colors.black,
          displayColor: Colors.black,
        );

    return ThemeData(
      brightness: blackColorScheme.brightness,
      colorScheme: blackColorScheme,
      useMaterial3: true,
      textTheme: themedText,
      primaryTextTheme: primaryTextTheme,
      typography: typography,
      scaffoldBackgroundColor: blackColorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: blackColorScheme.surface,
        titleTextStyle:
            themedText.titleLarge?.copyWith(color: blackColorScheme.onSurface),
        elevation: 0,
        centerTitle: false,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          overlayColor: stateLayer(blackColorScheme.surfaceTint),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.hPadding),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minVerticalPadding: 8,
      ),
      cardTheme: CardThemeData(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.hPadding,
          vertical: AppSpacing.vPaddingSmall,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 8,
        color: blackColorScheme.surfaceContainerHighest,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: blackColorScheme.outlineVariant),
        selectedColor: blackColorScheme.surfaceContainerHighest,
        backgroundColor: blackColorScheme.surfaceContainerLow,
        surfaceTintColor: blackColorScheme.surfaceTint,
        labelStyle: themedText.bodyMedium!,
        secondaryLabelStyle: themedText.bodyMedium!,
        showCheckmark: true,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return blackColorScheme.onSurface;
          }
          return blackColorScheme.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return blackColorScheme.surfaceContainerHighest;
          }
          return blackColorScheme.surfaceContainerHigh;
        }),
        trackOutlineColor:
            WidgetStatePropertyAll<Color>(blackColorScheme.outlineVariant),
      ),
      elevatedButtonTheme:
          ElevatedButtonThemeData(style: _elevatedButtonStyle(blackColorScheme)),
      filledButtonTheme:
          FilledButtonThemeData(style: _filledButtonStyle(blackColorScheme)),
      outlinedButtonTheme:
          OutlinedButtonThemeData(style: _outlinedButtonStyle(blackColorScheme)),
      textButtonTheme:
          TextButtonThemeData(style: _baseButtonStyle(blackColorScheme)),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: blackColorScheme.surfaceContainerHigh,
        backgroundColor: blackColorScheme.surfaceContainerLow,
        surfaceTintColor: blackColorScheme.surfaceTint,
        elevation: 1,
        height: 60,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        labelTextStyle: WidgetStateProperty.all(
          textTheme.labelLarge?.copyWith(color: blackColorScheme.onSurfaceVariant),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: blackColorScheme.secondaryContainer,
        foregroundColor: blackColorScheme.onSecondaryContainer,
        splashColor: stateLayer(blackColorScheme.surfaceTint)
            .resolve({WidgetState.pressed}),
        hoverColor:
            stateLayer(blackColorScheme.surfaceTint).resolve({WidgetState.hovered}),
        focusColor:
            stateLayer(blackColorScheme.surfaceTint).resolve({WidgetState.focused}),
      ),
      hoverColor: stateLayer(blackColorScheme.surfaceTint)
          .resolve({WidgetState.hovered, WidgetState.focused}),
      focusColor:
          stateLayer(blackColorScheme.surfaceTint).resolve({WidgetState.focused}),
      highlightColor:
          stateLayer(blackColorScheme.surfaceTint).resolve({WidgetState.pressed}),
      splashColor:
          stateLayer(blackColorScheme.surfaceTint).resolve({WidgetState.pressed}),
      splashFactory: InkSparkle.splashFactory,
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

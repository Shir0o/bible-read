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
        seedColor: const Color(0xFF6750A4), // M3 Purple
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.expressive,
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
          BorderSide(color: colorScheme.outline),
        ),
      );

  /// Filled button variant tuned for Material 3 visual language.
  static ButtonStyle _filledButtonStyle(ColorScheme colorScheme) =>
      _baseButtonStyle(colorScheme).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.12);
          }
          return colorScheme.primary;
        }),
        foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.38);
          }
          return colorScheme.onPrimary;
        }),
        shadowColor: WidgetStateProperty.all(colorScheme.shadow),
        surfaceTintColor: WidgetStateProperty.all(colorScheme.surfaceTint),
        elevation: WidgetStateProperty.resolveWith<double?>((states) {
          if (states.contains(WidgetState.disabled)) return 0;
          if (states.contains(WidgetState.pressed)) return 1.5;
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return 4.5;
          }
          return 3; // Standard M3 elevation
        }),
      );

  /// Complete [ThemeData] for the application.
  ///
  /// Adjust [colorScheme], [textTheme], or button themes to change the overall
  /// look and feel.
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
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          overlayColor: stateLayer(colorScheme.surfaceTint),
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
        elevation: 1, // Lower elevation for standard M3 cards
        color: colorScheme.surfaceContainer, // Standard M3 card color
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), // Standard M3 chip radius
        side: BorderSide(color: colorScheme.outlineVariant),
        selectedColor: colorScheme.secondaryContainer,
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent, // Disable tint
        labelStyle: themedText.labelLarge?.copyWith(color: colorScheme.onSurface),
        secondaryLabelStyle: themedText.labelLarge?.copyWith(color: colorScheme.onSecondaryContainer),
        showCheckmark: true,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onPrimary;
          }
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.surfaceContainerHighest;
        }),
        trackOutlineColor:
            WidgetStatePropertyAll<Color>(Colors.transparent),
      ),
      elevatedButtonTheme:
          ElevatedButtonThemeData(style: _elevatedButtonStyle(colorScheme)),
      filledButtonTheme:
          FilledButtonThemeData(style: _filledButtonStyle(colorScheme)),
      outlinedButtonTheme:
          OutlinedButtonThemeData(style: _outlinedButtonStyle(colorScheme)),
      textButtonTheme:
          TextButtonThemeData(style: _baseButtonStyle(colorScheme)),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: colorScheme.secondaryContainer, // Standard M3 active indicator
        backgroundColor: colorScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        height: 80, // Standard M3
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.all(
          textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
           if (states.contains(WidgetState.selected)) {
             return IconThemeData(color: colorScheme.onSecondaryContainer);
           }
           return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer, // Standard M3
        foregroundColor: colorScheme.onPrimaryContainer, // Standard M3
        splashColor: stateLayer(colorScheme.onPrimaryContainer)
            .resolve({WidgetState.pressed}),
        hoverColor:
            stateLayer(colorScheme.onPrimaryContainer).resolve({WidgetState.hovered}),
        focusColor:
            stateLayer(colorScheme.onPrimaryContainer).resolve({WidgetState.focused}),
            elevation: 6, // Standard M3 FAB
      ),
      hoverColor: stateLayer(colorScheme.primary)
          .resolve({WidgetState.hovered, WidgetState.focused}),
      focusColor:
          stateLayer(colorScheme.primary).resolve({WidgetState.focused}),
      highlightColor:
          stateLayer(colorScheme.primary).resolve({WidgetState.pressed}),
      splashColor:
          stateLayer(colorScheme.primary).resolve({WidgetState.pressed}),
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

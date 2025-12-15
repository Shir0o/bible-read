// Defines the global color scheme, fonts, spacing, and button styles.
import 'package:flutter/material.dart';

/// Provides the application's theme configuration.
///
/// Pass a [ColorScheme] to [appTheme] to change primary colors and adjust
/// [fontFamily] or [textTheme] to modify typography.
class AppTheme {
  // Desired primary font. If the IBM Plex Sans fonts are not bundled yet,
  // Flutter will fall back to the provided list below.
  static const String fontFamily = 'IBMPlexSans';

  static const RoundedRectangleBorder _buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)));

  static const EdgeInsetsGeometry _buttonPadding =
      EdgeInsets.symmetric(horizontal: 16, vertical: 12);

  // Unified typography using IBM Plex Sans with sensible fallbacks.
  static final TextTheme textTheme = TextTheme(
    displaySmall: const TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.w600,
      fontFamily: fontFamily,
      fontFamilyFallback: ['IBMPlexMono', 'sans-serif'],
    ),
    headlineMedium: const TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      fontFamily: fontFamily,
      fontFamilyFallback: ['IBMPlexMono', 'sans-serif'],
    ),
    titleLarge: const TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      fontFamily: fontFamily,
      fontFamilyFallback: ['IBMPlexMono', 'sans-serif'],
    ),
    titleMedium: const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      fontFamily: fontFamily,
      fontFamilyFallback: ['IBMPlexMono', 'sans-serif'],
    ),
    bodyLarge: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      fontFamily: fontFamily,
      fontFamilyFallback: ['IBMPlexMono', 'sans-serif'],
    ),
    bodyMedium: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      fontFamily: fontFamily,
      fontFamilyFallback: ['IBMPlexMono', 'sans-serif'],
    ),
    labelLarge: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      fontFamily: fontFamily,
      fontFamilyFallback: ['IBMPlexMono', 'sans-serif'],
    ),
  );

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
        overlayColor: WidgetStateProperty.resolveWith<Color?>(
          (states) {
            if (states.contains(WidgetState.pressed)) {
              return colorScheme.primaryContainer.withValues(alpha: 0.24);
            }
            if (states.contains(WidgetState.hovered)) {
              return colorScheme.primaryContainer.withValues(alpha: 0.16);
            }
            if (states.contains(WidgetState.focused)) {
              return colorScheme.primaryContainer.withValues(alpha: 0.20);
            }
            return null;
          },
        ),
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
        overlayColor: WidgetStateProperty.resolveWith<Color?>(
          (states) {
            if (states.contains(WidgetState.pressed)) {
              return colorScheme.primaryContainer.withValues(alpha: 0.28);
            }
            if (states.contains(WidgetState.hovered)) {
              return colorScheme.primaryContainer.withValues(alpha: 0.20);
            }
            if (states.contains(WidgetState.focused)) {
              return colorScheme.primaryContainer.withValues(alpha: 0.24);
            }
            return null;
          },
        ),
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
  static ThemeData appTheme(ColorScheme colorScheme) => ThemeData(
        brightness: colorScheme.brightness,
        colorScheme: colorScheme,
        useMaterial3: true,
        fontFamily: fontFamily,
        textTheme: textTheme,
        scaffoldBackgroundColor: colorScheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surface,
          titleTextStyle:
              textTheme.titleLarge?.copyWith(color: colorScheme.onSurface),
          elevation: 0,
          centerTitle: false,
        ),
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            overlayColor: WidgetStateProperty.resolveWith<Color?>(
              (states) {
                if (states.contains(WidgetState.pressed)) {
                  return colorScheme.primaryContainer.withValues(alpha: 0.20);
                }
                if (states.contains(WidgetState.hovered)) {
                  return colorScheme.primaryContainer.withValues(alpha: 0.14);
                }
                if (states.contains(WidgetState.focused)) {
                  return colorScheme.primaryContainer.withValues(alpha: 0.18);
                }
                return null;
              },
            ),
          ),
        ),
        listTileTheme: ListTileThemeData(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.hPadding),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          elevation: 1,
          color: colorScheme.surfaceContainerLow,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        chipTheme: ChipThemeData(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          side: BorderSide(color: colorScheme.outlineVariant),
          selectedColor: colorScheme.secondaryContainer,
          backgroundColor: colorScheme.surfaceContainerHigh,
          labelStyle: textTheme.bodyMedium!,
          secondaryLabelStyle: textTheme.bodyMedium!,
          showCheckmark: true,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.primary;
            }
            return colorScheme.onSurfaceVariant;
          }),
          trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.primaryContainer;
            }
            return colorScheme.surfaceContainerHigh;
          }),
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
          indicatorColor: colorScheme.secondaryContainer,
          backgroundColor: colorScheme.surfaceContainerLow,
          elevation: 1,
          height: 60,
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          labelTextStyle: WidgetStateProperty.all(
            textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: colorScheme.secondaryContainer,
          foregroundColor: colorScheme.onSecondaryContainer,
          splashColor: colorScheme.onSecondaryContainer.withValues(alpha: 0.24),
          hoverColor: colorScheme.onSecondaryContainer.withValues(alpha: 0.16),
          focusColor: colorScheme.onSecondaryContainer.withValues(alpha: 0.20),
        ),
        hoverColor: colorScheme.primary.withValues(alpha: 0.04),
        focusColor: colorScheme.primary.withValues(alpha: 0.08),
        highlightColor: colorScheme.primary.withValues(alpha: 0.10),
        splashColor: colorScheme.primary.withValues(alpha: 0.14),
        splashFactory: InkSparkle.splashFactory,
      );
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

// Shared styling helpers and text styles used across the app's widgets.
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Provides reusable widget styles and builders for consistent design.
///
/// Use these helpers when constructing common UI elements like cards and
/// app bars to ensure the same look and feel throughout the app.
class CommonStyles {
  static BoxDecoration backgroundDecoration(ColorScheme colorScheme) =>
      BoxDecoration(
        color: colorScheme.surface,
      );

  static TextStyle appBarTitleText(ColorScheme colorScheme) =>
      AppTheme.textTheme.titleLarge!.copyWith(
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurface,
      );

  /// Builds a card with the app's standard padding and rounded corners.
  ///
  /// [child] is placed inside the card.
  /// [margin] optionally overrides the default margin.
  ///
  /// Returns a [Card] widget styled for the application.
  static Card buildCard({
    required BuildContext context,
    required Widget child,
    EdgeInsetsGeometry? margin,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: margin ??
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.hPadding,
            vertical: AppSpacing.vPaddingSmall,
          ),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.hPadding),
        child: child,
      ),
    );
  }

  /// Builds a card that provides an InkWell overlay when tapped/hovered.
  static Card buildTappableCard({
    required BuildContext context,
    required Widget child,
    EdgeInsetsGeometry? margin,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(16);
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: radius),
      margin: margin ??
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.hPadding,
            vertical: AppSpacing.vPaddingSmall,
          ),
      color: colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.pressed)) {
            return colorScheme.primaryContainer.withValues(alpha: 0.16);
          }
          if (states.contains(WidgetState.hovered)) {
            return colorScheme.primaryContainer.withValues(alpha: 0.10);
          }
          if (states.contains(WidgetState.focused)) {
            return colorScheme.primaryContainer.withValues(alpha: 0.12);
          }
          return null;
        }),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.hPadding),
          child: child,
        ),
      ),
    );
  }

  /// Creates an [AppBar] with the application's default styling.
  ///
  /// [title] is displayed as the app bar's title.
  /// [actions] are optional widgets shown on the right.
  /// [leading] is an optional widget displayed before the title.
  /// [automaticallyImplyLeading] determines whether to automatically include a
  /// back button when possible.
  ///
  /// Returns a [PreferredSizeWidget] configured app bar.
  static PreferredSizeWidget buildAppBar(
    BuildContext context,
    String title, {
    List<Widget>? actions,
    Widget? leading,
    bool automaticallyImplyLeading = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppBar(
      title: Text(title, style: appBarTitleText(colorScheme)),
      backgroundColor: colorScheme.surface,
      actions: actions,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
    );
  }
}

/// Defines reusable text styles for displaying content.
///
/// Use [subtitle] for section headings and [body] for regular content text.
class AppTextStyles {
  static const TextStyle subtitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    fontFamily: AppTheme.fontFamily,
    fontFamilyFallback: ['IBMPlexMono', 'sans-serif'],
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontFamily: AppTheme.fontFamily,
    fontFamilyFallback: ['IBMPlexMono', 'sans-serif'],
  );
}

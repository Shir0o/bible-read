// Shared styling helpers and text styles used across the app's widgets.
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Provides reusable widget styles and builders for consistent design.
///
/// Use these helpers when constructing common UI elements like cards and
/// app bars to ensure the same look and feel throughout the app.
class CommonStyles {
  static BoxDecoration backgroundDecoration(ColorScheme colorScheme) =>
      BoxDecoration(color: colorScheme.surface);

  static TextStyle appBarTitleText(ColorScheme colorScheme) =>
      AppTheme.textTheme.titleLarge!.copyWith(
        fontFamily: AppTheme.fontSerif,
        fontWeight: FontWeight.w600,
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
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        side: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
      ),
      margin: margin ??
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.hPadding,
            vertical: AppSpacing.vPaddingSmall,
          ),
      color: colorScheme.surfaceContainerLowest,
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
    final radius = BorderRadius.circular(AppSpacing.rCard);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
      ),
      margin: margin ??
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.hPadding,
            vertical: AppSpacing.vPaddingSmall,
          ),
      color: colorScheme.surfaceContainerLowest,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.hPadding),
          child: child,
        ),
      ),
    );
  }

  /// Builds a bordered, full-bleed card (no internal padding).
  ///
  /// Unlike [buildCard], this does not add inner padding, so it suits grouping
  /// list rows separated by dividers that span edge-to-edge — each row controls
  /// its own padding. Used by the settings screens.
  static Card buildBorderedCard({
    required BuildContext context,
    required Widget child,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      margin: margin,
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        side: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
      ),
      child: child,
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
/// Use these getters to access standardized typography throughout the app.
class AppTextStyles {
  static TextStyle title(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge!;

  static TextStyle subtitle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!;

  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge!;

  static TextStyle bodySmall(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!;

  static TextStyle caption(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall!;

  /// Serif section title (Spectral 19 / 500). Matches the design's
  /// `.section-title` rule; equivalent to the themed [titleLarge].
  static TextStyle sectionTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge!;

  /// Serif scripture body (Spectral, line-height 1.82). Pass [scale] to honour
  /// the reader's font-size setting (the design's `--read-size`).
  static TextStyle scripture(BuildContext context, {double scale = 1}) =>
      TextStyle(
        fontFamily: AppTheme.fontSerif,
        fontSize: 19 * scale,
        fontWeight: FontWeight.w400,
        height: 1.82,
        color: Theme.of(context).colorScheme.onSurface,
      );

  /// Uppercase eyebrow label (Hanken 11 / 700 / wide tracking). Apply the
  /// returned style to text you have already upper-cased.
  static TextStyle eyebrow(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall!;
}

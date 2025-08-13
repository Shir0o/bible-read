// Shared styling helpers and text styles used across the app's widgets.
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Provides reusable widget styles and builders for consistent design.
///
/// Use these helpers when constructing common UI elements like cards and
/// app bars to ensure the same look and feel throughout the app.
class CommonStyles {
  static const BoxDecoration backgroundGradient = BoxDecoration(
    color: AppTheme.backgroundColor,
  );

  static const TextStyle appBarTitleText = TextStyle(
    fontFamily: AppTheme.fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  /// Builds a card with the app's standard padding and rounded corners.
  ///
  /// [child] is placed inside the card.
  /// [margin] optionally overrides the default margin.
  ///
  /// Returns a [Card] widget styled for the application.
  static Card buildCard({required Widget child, EdgeInsetsGeometry? margin}) {
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: child,
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
    String title, {
    List<Widget>? actions,
    Widget? leading,
    bool automaticallyImplyLeading = true,
  }) {
    return AppBar(
      title: Text(title, style: appBarTitleText),
      backgroundColor: AppTheme.backgroundColor,
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
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontFamily: AppTheme.fontFamily,
  );
}

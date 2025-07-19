// lib/widgets/common_styles.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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

  static PreferredSizeWidget buildAppBar(String title,
      {List<Widget>? actions}) {
    return AppBar(
      title: Text(title, style: appBarTitleText),
      backgroundColor: AppTheme.backgroundColor,
      actions: actions,
    );
  }
}

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

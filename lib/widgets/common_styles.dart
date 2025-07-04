// lib/widgets/common_styles.dart
import 'package:flutter/material.dart';

class CommonStyles {
  static const BoxDecoration backgroundGradient = BoxDecoration(
    color: Colors.black,
  );

  static const TextStyle appBarTitleText = TextStyle(
    fontFamily: 'IBMPlexMono',
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

  static PreferredSizeWidget buildAppBar(String title) {
    return AppBar(
      title: Text(title, style: appBarTitleText),
      backgroundColor: Colors.black, // Enforce black background for app bar
    );
  }
}

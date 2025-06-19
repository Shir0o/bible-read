// lib/widgets/common_styles.dart
import 'package:flutter/material.dart';

class CommonStyles {
  static const BoxDecoration backgroundGradient = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFFFDFCFB), Color(0xFFE2D1C3)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  static const RoundedRectangleBorder roundedAppBar = RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
  );

  static const TextStyle appBarTitleText = TextStyle(
    fontFamily: 'Poppins',
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: Colors.black,
  );

  static const Color appBarColor = Color(0xFF673AB7); // Example purple

  static Card buildCard({required Widget child}) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: child,
      ),
    );
  }

  static PreferredSizeWidget buildAppBar(String title) {
    return AppBar(
      title: Text(title, style: appBarTitleText),
      backgroundColor: appBarColor,
      shape: roundedAppBar,
    );
  }
}
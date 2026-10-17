import 'package:flutter/material.dart';

/// Illustration palette for the check-in celebration page: the time-of-day sky
/// gradients, the sun, and the ink/cream chrome drawn over them. These are
/// hand-tuned artwork colours, not UI chrome, so they sit outside the
/// [ColorScheme] and are named here instead of inlined in the page.
class CheckInSky {
  CheckInSky._();

  // Sky gradients, top to bottom.
  static const List<Color> dawn = [
    Color(0xFFFFD3A6),
    Color(0xFFFFB4B8),
    Color(0xFFD9BDE8),
    Color(0xFFC3BCEE),
  ];
  static const List<Color> day = [
    Color(0xFFBFE6F7),
    Color(0xFFD8ECF6),
    Color(0xFFEFE6D8),
    Color(0xFFF6E9D4),
  ];
  static const List<Color> dusk = [
    Color(0xFFF9B98A),
    Color(0xFFE997AE),
    Color(0xFF9A7FCB),
    Color(0xFF6C5EA8),
  ];
  static const List<Color> night = [
    Color(0xFF241F3C),
    Color(0xFF332A55),
    Color(0xFF463A72),
    Color(0xFF5A4B8C),
  ];

  // Chrome drawn over the sky.
  static const Color ink = Color(0xFF2A2438);
  static const Color cream = Color(0xFFFFF3DE);
  static const Color nightSunBorder = Color(0xFF1A1630);
  static const Color buttonFill = Color(0xFFFFFDF8);

  // The flood of light behind the sun.
  static const List<Color> flood = [
    Color(0xFFFFF2C4),
    Color(0xFFFFD470),
    Color(0xFFF6A93C),
  ];

  // The sun disc.
  static const List<Color> sun = [Color(0xFFFFE9A8), Color(0xFFFFC24D)];
}

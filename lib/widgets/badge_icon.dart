import 'package:flutter/material.dart';

/// Displays a badge image with an optional locked overlay.
class BadgeIcon extends StatelessWidget {
  /// Path to the badge asset.
  final String assetPath;

  /// Whether the badge is locked.
  final bool locked;

  /// Size of the badge icon.
  final double size;

  /// Creates a [BadgeIcon].
  const BadgeIcon({
    super.key,
    required this.assetPath,
    this.locked = false,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: locked ? 0.3 : 1.0,
          child: Image.asset(
            assetPath,
            width: size,
            height: size,
          ),
        ),
        if (locked)
          const Icon(
            Icons.lock,
            color: Colors.white70,
            size: 16,
          ),
      ],
    );
  }
}

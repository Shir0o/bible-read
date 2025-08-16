import 'package:flutter/material.dart';

/// Displays a badge image or icon with an optional locked overlay.
///
/// ```dart
/// // Display a network image
/// const BadgeIcon(imageUrl: 'https://example.com/badge.png');
///
/// // Display an icon
/// const BadgeIcon(iconData: Icons.star);
/// ```
class BadgeIcon extends StatelessWidget {
  /// URL of the badge image.
  final String? imageUrl;

  /// Icon to display for the badge.
  final IconData? iconData;

  /// Whether the badge is locked.
  final bool locked;

  /// Size of the badge icon.
  final double size;

  /// Creates a [BadgeIcon]. Provide exactly one of [imageUrl] or [iconData].
  const BadgeIcon({
    super.key,
    this.imageUrl,
    this.iconData,
    this.locked = false,
    this.size = 24,
  }) : assert(
          (imageUrl != null ? 1 : 0) + (iconData != null ? 1 : 0) == 1,
          'Provide exactly one badge source.',
        );

  @override
  Widget build(BuildContext context) {
    final Widget image;
    if (imageUrl != null) {
      image = Image.network(
        imageUrl!,
        width: size,
        height: size,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return SizedBox(
            width: size,
            height: size,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) =>
            Icon(Icons.image_not_supported, size: size),
      );
    } else {
      image = Icon(iconData!, size: size);
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: locked ? 0.3 : 1.0,
          child: image,
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

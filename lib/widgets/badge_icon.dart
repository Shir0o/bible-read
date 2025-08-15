import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Displays a badge image or icon with an optional locked overlay.
///
/// **Migration guide**
///
/// ```dart
/// // Previously:
/// const BadgeIcon(assetPath: 'assets/badges/gold.png');
///
/// // Now:
/// const BadgeIcon(assetPath: 'assets/badges/gold.png'); // PNG
/// const BadgeIcon(svgAsset: 'assets/badges/gold.svg'); // SVG
/// const BadgeIcon(iconData: Icons.star); // IconData
/// ```
class BadgeIcon extends StatelessWidget {
  /// Path to the badge PNG asset.
  final String? assetPath;

  /// Path to the badge SVG asset.
  final String? svgAsset;

  /// Icon to display for the badge.
  final IconData? iconData;

  /// Whether the badge is locked.
  final bool locked;

  /// Size of the badge icon.
  final double size;

  /// Creates a [BadgeIcon]. Provide exactly one of [assetPath], [svgAsset],
  /// or [iconData].
  const BadgeIcon({
    super.key,
    this.assetPath,
    this.svgAsset,
    this.iconData,
    this.locked = false,
    this.size = 24,
  }) : assert(
          (assetPath != null ? 1 : 0) +
                  (svgAsset != null ? 1 : 0) +
                  (iconData != null ? 1 : 0) ==
              1,
          'Provide exactly one badge source.',
        );

  @override
  Widget build(BuildContext context) {
    final Widget image;
    if (assetPath != null) {
      image = Image.asset(
        assetPath!,
        width: size,
        height: size,
      );
    } else if (svgAsset != null) {
      image = SvgPicture.asset(
        svgAsset!,
        width: size,
        height: size,
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

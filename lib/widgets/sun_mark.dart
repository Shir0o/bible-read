import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The small gold sun mark icon — shown on the Home header next to the profile
/// picture. Supports two states:
///   • Unmarked (`done: false`): clean golden sun circle disc.
///   • Marked (`done: true`): golden sun circle disc containing a checkmark icon.
class SunMark extends StatelessWidget {
  final double size;
  final bool done;
  final VoidCallback? onTap;

  /// Width of the ink outline. Smaller inline marks use a lighter 1.5.
  final double borderWidth;

  const SunMark({
    super.key,
    this.size = 32.0,
    required this.done,
    this.onTap,
    this.borderWidth = 2,
  });

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final borderColor = appColors.sunInk;

    final sunWidget = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: borderWidth),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: appColors.sunGradient,
        ),
        boxShadow: [
          BoxShadow(
            color: borderColor.withAlpha(0x1F),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: done
              ? Icon(
                  Icons.check_rounded,
                  key: const ValueKey('sun_mark_check'),
                  size: size * 0.58,
                  color: borderColor,
                )
              : SizedBox(
                  key: const ValueKey('sun_mark_empty'),
                  width: size * 0.58,
                  height: size * 0.58,
                ),
        ),
      ),
    );

    if (onTap == null) return sunWidget;

    final targetSize = size < 44.0 ? 44.0 : size;

    return Semantics(
      button: true,
      label: done ? 'You read today — open check-in' : 'Open today’s check-in',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: targetSize,
          height: targetSize,
          child: Center(child: sunWidget),
        ),
      ),
    );
  }
}

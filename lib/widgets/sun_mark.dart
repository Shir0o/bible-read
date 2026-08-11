import 'package:flutter/material.dart';

/// The small gold sun mark icon — shown on the Home header next to the profile
/// picture. Supports two states:
///   • Unmarked (`done: false`): clean golden sun circle disc.
///   • Marked (`done: true`): golden sun circle disc containing a checkmark icon.
class SunMark extends StatelessWidget {
  final double size;
  final bool done;
  final VoidCallback? onTap;

  const SunMark({super.key, this.size = 32.0, required this.done, this.onTap});

  @override
  Widget build(BuildContext context) {
    const borderColor = Color(0xFF2A2438);
    const gradientColors = [Color(0xFFFFE9A8), Color(0xFFFFC24D)];

    final sunWidget = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F2A2438),
            blurRadius: 4,
            offset: Offset(0, 2),
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

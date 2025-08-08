import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Overlay animation shown on successful actions.
class SuccessAnimation extends StatelessWidget {
  /// Callback invoked when the animation is dismissed.
  final VoidCallback onDismiss;

  const SuccessAnimation({super.key, required this.onDismiss});

  /// Displays the success animation using an [Overlay] above the current
  /// context.
  static void show(BuildContext context) {
    final overlay = Overlay.of(context);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: SuccessAnimation(
          onDismiss: () => entry.remove(),
        ),
      ),
    );
    overlay.insert(entry);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (entry.mounted) entry.remove();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onDismiss,
        child: Lottie.asset(
          'assets/animations/success.json',
          repeat: false,
        ),
      ),
    );
  }
}


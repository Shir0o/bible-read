import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Overlay animation shown on successful actions.
class SuccessAnimation extends StatelessWidget {
  /// Callback invoked when the animation is dismissed.
  final VoidCallback onDismiss;

  const SuccessAnimation({super.key, required this.onDismiss});

  /// Displays the success animation using an [Overlay] above the current
  /// context.
  static Future<void> show(BuildContext context) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: SuccessAnimation(onDismiss: () => entry.remove()),
      ),
    );
    overlay.insert(entry);
    return Future<void>.delayed(const Duration(seconds: 2), () {
      if (entry.mounted) entry.remove();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onDismiss,
        child: Lottie.network(
          'https://raw.githubusercontent.com/xvrh/lottie-flutter/master/example/assets/lottiefiles/scan_qr_code_success.json',
          repeat: false,
          frameBuilder: (context, child, composition) {
            if (composition == null) {
              return const SizedBox(
                width: 120,
                height: 120,
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return child;
          },
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 120,
          ),
        ),
      ),
    );
  }
}

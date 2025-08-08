import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A button that provides press feedback via a scale animation and
/// optionally shows a loading indicator.
class AnimatedActionButton extends StatefulWidget {
  /// Called when the button is pressed and not loading.
  final VoidCallback? onPressed;

  /// The widget below this widget in the tree.
  final Widget child;

  /// Whether to display a loading spinner and disable the button.
  final bool isLoading;

  /// Whether to trigger a light haptic feedback on press.
  final bool enableHapticFeedback;

  /// Creates an [AnimatedActionButton].
  const AnimatedActionButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isLoading = false,
    this.enableHapticFeedback = false,
  });

  @override
  State<AnimatedActionButton> createState() => _AnimatedActionButtonState();
}

class _AnimatedActionButtonState extends State<AnimatedActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.enableHapticFeedback) {
      HapticFeedback.lightImpact();
    }
    _controller.animateTo(0.95, curve: Curves.easeInOut);
  }

  void _onTapUp([TapUpDetails? details]) {
    _controller.animateTo(1.0, curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('animated_action_button_detector'),
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapUp,
      behavior: HitTestBehavior.translucent,
      child: ScaleTransition(
        scale: _controller,
        child: ElevatedButton(
          onPressed: widget.isLoading ? null : widget.onPressed,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: widget.isLoading
                ? const SizedBox(
                    key: ValueKey('spinner'),
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : KeyedSubtree(
                    key: const ValueKey('label'),
                    child: widget.child,
                  ),
          ),
        ),
      ),
    );
  }

  @visibleForTesting
  Animation<double> get animation => _controller;
}

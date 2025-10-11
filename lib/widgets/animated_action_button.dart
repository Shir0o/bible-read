import 'dart:async';

import 'package:flutter/material.dart';

import '../services/vibration_service.dart';

/// A button that provides press feedback via modern Material motion and
/// optionally shows a loading indicator.
class AnimatedActionButton extends StatefulWidget {
  /// Called when the button is pressed and not loading.
  final VoidCallback? onPressed;

  /// The widget below this widget in the tree.
  final Widget child;

  /// Whether to display a loading spinner and disable the button.
  final bool isLoading;

  /// Whether to trigger a light vibration on press.
  ///
  /// Defaults to `true`.
  final bool enableHapticFeedback;

  /// Service used to trigger vibrations.
  final VibrationService vibrationService;

  /// Creates an [AnimatedActionButton].
  const AnimatedActionButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isLoading = false,
    this.enableHapticFeedback = true,
    VibrationService? vibrationService,
  }) : vibrationService = vibrationService ?? const VibrationService();

  @override
  State<AnimatedActionButton> createState() => _AnimatedActionButtonState();
}

class _AnimatedActionButtonState extends State<AnimatedActionButton>
    with SingleTickerProviderStateMixin {
  static const double _baseScale = 1.0;
  static const double _pressedScale = 0.96;
  static const double _hoveredScale = 1.02;
  static const double _minScale = 0.94;

  static const double _restElevation = 3;
  static const double _hoverElevation = 6;
  static const double _pressedElevation = 1;
  static const double _disabledElevation = 0;

  static const BorderRadius _cornerRadius =
      BorderRadius.all(Radius.circular(14));

  late final AnimationController _scaleController;
  late final WidgetStatesController _statesController;
  late final ValueNotifier<double> _elevationNotifier;
  bool _elevationUpdateScheduled = false;
  double _pendingElevationValue = _restElevation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      lowerBound: _minScale,
      upperBound: _hoveredScale,
      value: _baseScale,
    );
    _statesController = WidgetStatesController();
    _statesController.addListener(_handleStatesChanged);
    _elevationNotifier = ValueNotifier<double>(_restElevation);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _handleStatesChanged();
      }
    });
  }

  @override
  void dispose() {
    _statesController.removeListener(_handleStatesChanged);
    _statesController.dispose();
    _elevationNotifier.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.enableHapticFeedback) {
      unawaited(widget.vibrationService.tap());
    }
  }

  void _handleStatesChanged() {
    if (!mounted) return;
    final states = _statesController.value;
    final bool disabled = states.contains(WidgetState.disabled);
    final bool pressed = states.contains(WidgetState.pressed);
    final bool hovered = states.contains(WidgetState.hovered);
    final bool focused = states.contains(WidgetState.focused);

    final double targetScale = (disabled
            ? _baseScale
            : pressed
                ? _pressedScale
                : (hovered || focused)
                    ? _hoveredScale
                    : _baseScale)
        .clamp(_minScale, _hoveredScale);
    final double targetElevation = disabled
        ? _disabledElevation
        : pressed
            ? _pressedElevation
            : (hovered || focused)
                ? _hoverElevation
                : _restElevation;

    final Duration duration = pressed
        ? const Duration(milliseconds: 90)
        : const Duration(milliseconds: 220);
    final Curve curve =
        pressed ? Curves.easeInOutCubicEmphasized : Curves.easeOutBack;

    _scaleController.animateTo(targetScale, duration: duration, curve: curve);

    _queueElevationUpdate(targetElevation);
  }

  void _queueElevationUpdate(double targetElevation) {
    if ((_pendingElevationValue - targetElevation).abs() <= 0.01 &&
        !_elevationUpdateScheduled) {
      return;
    }

    _pendingElevationValue = targetElevation;
    if (_elevationUpdateScheduled) {
      return;
    }

    _elevationUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _elevationUpdateScheduled = false;
        return;
      }
      _elevationUpdateScheduled = false;
      final value = _pendingElevationValue;
      if ((_elevationNotifier.value - value).abs() > 0.01) {
        _elevationNotifier.value = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shadowBaseColor = colorScheme.primary.withValues(alpha: 0.32);

    return Listener(
      key: const Key('animated_action_button_listener'),
      behavior: HitTestBehavior.translucent,
      onPointerDown: widget.enableHapticFeedback ? _handlePointerDown : null,
      child: ValueListenableBuilder<double>(
        valueListenable: _elevationNotifier,
        builder: (context, elevation, _) {
          final shadows = elevation == 0
              ? const <BoxShadow>[]
              : <BoxShadow>[
                  BoxShadow(
                    color: shadowBaseColor,
                    blurRadius: 3 + (elevation * 2),
                    spreadRadius: 0.2 * elevation,
                    offset: Offset(0, 0.4 * elevation),
                  ),
                ];

          return ScaleTransition(
            scale: _scaleController,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: _cornerRadius,
                boxShadow: shadows,
              ),
              child: FilledButton(
                statesController: _statesController,
                onPressed: widget.isLoading ? null : widget.onPressed,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: widget.isLoading
                      ? SizedBox(
                          key: const ValueKey('spinner'),
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              colorScheme.onPrimary,
                            ),
                          ),
                        )
                      : KeyedSubtree(
                          key: const ValueKey('label'),
                          child: widget.child,
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @visibleForTesting
  Animation<double> get animation => _scaleController;

  @visibleForTesting
  WidgetStatesController get statesController => _statesController;
}

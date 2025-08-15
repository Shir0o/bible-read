import 'package:flutter/material.dart';

/// Tappable switch that briefly scales on toggle.
class ReadSwitchTile extends StatefulWidget {
  /// Whether the switch is on.
  final bool value;

  /// Called when the switch should change state.
  final ValueChanged<bool>? onChanged;

  /// Whether to play the scale animation when toggled.
  final bool animate;

  /// Creates an animated [ReadSwitchTile].
  const ReadSwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
  }) : animate = true;

  /// Creates a [ReadSwitchTile] without animation.
  const ReadSwitchTile.noAnimation({
    super.key,
    required this.value,
    required this.onChanged,
  }) : animate = false;

  @override
  State<ReadSwitchTile> createState() => _ReadSwitchTileState();
}

class _ReadSwitchTileState extends State<ReadSwitchTile>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 200),
        lowerBound: 0.8,
        upperBound: 1.0,
        value: 1.0,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _triggerAnimation() {
    _controller?.forward(from: _controller!.lowerBound);
  }

  void _handleChanged(bool newValue) {
    widget.onChanged?.call(newValue);
    if (widget.animate) _triggerAnimation();
  }

  @override
  Widget build(BuildContext context) {
    final switchWidget = Switch(
      value: widget.value,
      onChanged: widget.onChanged == null ? null : _handleChanged,
      activeThumbColor: Colors.green,
    );

    final child = widget.animate
        ? ScaleTransition(scale: _controller!, child: switchWidget)
        : switchWidget;

    return InkWell(
      onTap:
          widget.onChanged == null ? null : () => _handleChanged(!widget.value),
      child: child,
    );
  }
}

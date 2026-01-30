import 'dart:async';
import 'package:flutter/material.dart';
import '../services/vibration_service.dart';

class ReadSwitchTile extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final VibrationService? vibrationService;
  final bool _animate;

  const ReadSwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.vibrationService,
  }) : _animate = true;

  const ReadSwitchTile.noAnimation({
    super.key,
    required this.value,
    required this.onChanged,
    this.vibrationService,
  }) : _animate = false;

  @override
  State<ReadSwitchTile> createState() => _ReadSwitchTileState();
}

class _ReadSwitchTileState extends State<ReadSwitchTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      value: 1.0,
      lowerBound: 0.95,
      upperBound: 1.0,
    );
    _scale = _controller;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.onChanged != null) {
      if (widget.vibrationService != null) {
        unawaited(widget.vibrationService!.lightImpact());
      }
      widget.onChanged!(!widget.value);
      if (widget._animate) {
        _controller.value = 0.95;
        _controller.forward();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _handleTap,
      child: ScaleTransition(
        scale: _scale,
        child: Switch(
          value: widget.value,
          onChanged: widget.onChanged == null ? null : (v) => _handleTap(),
        ),
      ),
    );
  }
}

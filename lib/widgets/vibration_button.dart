import 'dart:async';

import 'package:flutter/material.dart';

import '../services/vibration_service.dart';

/// Elevated button that triggers a light vibration when pressed.
class VibrationButton extends StatelessWidget {
  /// Callback invoked after the vibration.
  final VoidCallback onPressed;

  /// Child widget to display inside the button.
  final Widget child;

  /// Service used to trigger vibrations.
  final VibrationService vibrationService;

  /// Creates a [VibrationButton].
  const VibrationButton({
    super.key,
    required this.onPressed,
    required this.child,
    VibrationService? vibrationService,
  }) : vibrationService = vibrationService ?? const VibrationService();

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        unawaited(vibrationService.lightImpact());
        onPressed();
      },
      child: child,
    );
  }
}

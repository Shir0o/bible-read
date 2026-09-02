import 'dart:async';

import 'package:flutter/material.dart';

import '../services/vibration_service.dart';
import '../theme/app_theme.dart';

/// Visual scale of a [StepperControl].
enum StepperSize {
  /// Pace control on the plan form — larger numeral.
  large,

  /// Inside a day row, where the reference beside it is the focus.
  compact,
}

/// A minus / value / plus control for choosing a small whole number.
///
/// Both buttons keep a 44px touch target. At [min] the decrement is dimmed and
/// inert — a greyed control that still fires would let a press that changes
/// nothing mark a day as hand-set.
class StepperControl extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  /// Accessibility label for the decrement button, e.g. 'One chapter fewer'.
  final String decrementLabel;

  /// Accessibility label for the increment button.
  final String incrementLabel;

  final StepperSize size;
  final Key? decrementKey;
  final Key? incrementKey;
  final VibrationService vibrationService;

  const StepperControl({
    super.key,
    required this.value,
    required this.onChanged,
    required this.decrementLabel,
    required this.incrementLabel,
    this.min = 1,
    this.max = 20,
    this.size = StepperSize.large,
    this.decrementKey,
    this.incrementKey,
    this.vibrationService = const VibrationService(),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);
    final canDecrement = value > min;
    final canIncrement = value < max;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.rField),
        border: Border.all(color: appColors.border),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            key: decrementKey,
            icon: Icons.remove,
            label: decrementLabel,
            enabled: canDecrement,
            onTap: () => _step(-1),
            vibrationService: vibrationService,
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 26),
            alignment: Alignment.center,
            child: Text(
              '$value',
              style: TextStyle(
                fontFamily: AppTheme.fontSerif,
                fontSize: size == StepperSize.large ? 20 : 17,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          _StepButton(
            key: incrementKey,
            icon: Icons.add,
            label: incrementLabel,
            enabled: canIncrement,
            onTap: () => _step(1),
            vibrationService: vibrationService,
          ),
        ],
      ),
    );
  }

  void _step(int delta) {
    final next = (value + delta).clamp(min, max);
    if (next != value) onChanged(next);
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final VibrationService vibrationService;

  const _StepButton({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.vibrationService,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: InkWell(
        onTap: enabled
            ? () {
                unawaited(vibrationService.lightImpact());
                onTap();
              }
            : null,
        borderRadius: BorderRadius.circular(AppSpacing.rChip),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            size: 18,
            color: enabled
                ? appColors.primaryPress
                : colorScheme.outline.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

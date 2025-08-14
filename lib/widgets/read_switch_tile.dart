import 'package:flutter/material.dart';

/// Row widget with a [Switch] and label that animates when [value] changes.
class ReadSwitchTile extends StatelessWidget {
  /// Whether the switch is on.
  final bool value;

  /// Called when the switch should change state.
  final ValueChanged<bool>? onChanged;

  /// Text label shown next to the switch.
  final String label;

  /// Creates a [ReadSwitchTile].
  const ReadSwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Switch(
              key: ValueKey<bool>(value),
              value: value,
              onChanged: onChanged,
              activeTrackColor: Colors.green,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: Text(
                label,
                key: ValueKey<bool>(value),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

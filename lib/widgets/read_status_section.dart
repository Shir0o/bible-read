import 'dart:async';

import 'package:flutter/material.dart';
import 'read_switch_tile.dart';
import '../services/vibration_service.dart';

class ReadStatusSection extends StatelessWidget {
  final bool toggleLoading;
  final bool readToday;
  final Set<String> readDates;
  final VoidCallback? onToggle;
  final int? streakFreezesLeft;
  final VibrationService? vibrationService;

  const ReadStatusSection({
    super.key,
    required this.toggleLoading,
    required this.readToday,
    required this.readDates,
    this.onToggle,
    this.streakFreezesLeft,
    this.vibrationService,
  });

  @override
  Widget build(BuildContext context) {
    if (toggleLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        ReadSwitchTile(
          value: readToday,
          onChanged: onToggle == null ? null : (_) => onToggle!(),
          vibrationService: vibrationService,
        ),
        if (streakFreezesLeft != null) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Streak freezes left: $streakFreezesLeft'),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.info_outline, size: 16),
                tooltip: 'About streak freezes',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  unawaited(vibrationService?.lightImpact());
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      content: const Text(
                        'Each month includes two automatic grace credits to freeze a missed day. '
                        'Every 15-day streak earns one extra credit.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ],
    );
  }
}

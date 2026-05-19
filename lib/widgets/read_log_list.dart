import 'package:flutter/material.dart';

import '../models/read_log.dart';
import '../services/vibration_service.dart';
import 'feed_card.dart';

/// Displays a list of read log entries using the new FeedCard design.
class ReadLogList extends StatelessWidget {
  /// Log entries to show.
  final List<ReadLog> logs;

  /// Callback when the like button is pressed.
  final void Function(String uid) onToggleLike;

  const ReadLogList({
    super.key,
    required this.logs,
    required this.onToggleLike,
    this.vibrationService,
  });

  final VibrationService? vibrationService;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return FeedCard(
          log: log,
          onToggleLike: () => onToggleLike(log.uid),
          vibrationService: vibrationService,
        );
      },
      padding: const EdgeInsets.only(bottom: 24),
    );
  }
}

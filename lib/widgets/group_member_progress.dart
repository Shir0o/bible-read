import 'package:flutter/material.dart';

/// Displays a group member's reading progress for the current day.
class GroupMemberProgress extends StatelessWidget {
  /// Display name of the member.
  final String name;

  /// Completion percentage expressed as a value between 0 and 1.
  final double completion;

  const GroupMemberProgress({
    super.key,
    required this.name,
    required this.completion,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = completion.clamp(0.0, 1.0).toDouble();
    final percent = (clamped * 100).round();

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(name),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: LinearProgressIndicator(value: clamped),
      ),
      trailing: Text('$percent%'),
    );
  }
}

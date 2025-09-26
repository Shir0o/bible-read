import 'package:flutter/material.dart';

import '../models/group_schedule.dart';

/// List tile displaying a group's reading assignment for a single day.
class ScheduleItemTile extends StatelessWidget {
  /// Schedule entry to display.
  final GroupSchedule schedule;

  /// Callback when the edit button is tapped.
  final VoidCallback? onEdit;

  /// Callback when the delete button is tapped.
  final VoidCallback? onDelete;

  /// Whether the current user has marked this date as read.
  final bool? currentUserRead;

  /// Toggle handler to mark/unmark as read for the current user.
  final ValueChanged<bool>? onToggleRead;

  /// Callback when the tile is tapped.
  final VoidCallback? onTap;

  /// Creates a [ScheduleItemTile].
  const ScheduleItemTile({
    super.key,
    required this.schedule,
    this.onEdit,
    this.onDelete,
    this.currentUserRead,
    this.onToggleRead,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateString = schedule.date.toIso8601String().split('T').first;
    final actions = <Widget>[];
    if (onEdit != null) {
      actions.add(IconButton(
        icon: const Icon(Icons.edit),
        tooltip: 'Edit',
        onPressed: onEdit,
      ));
    }
    if (onDelete != null) {
      actions.add(IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete',
        onPressed: onDelete,
      ));
    }
    if (onToggleRead != null && currentUserRead != null) {
      actions.add(Checkbox(
        value: currentUserRead,
        onChanged: (v) => onToggleRead?.call(v ?? false),
      ));
    }

    return ListTile(
      title: Text(dateString),
      subtitle: Text(schedule.chapters.join(', ')),
      onTap: onTap,
      trailing: actions.isEmpty
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: actions),
    );
  }
}

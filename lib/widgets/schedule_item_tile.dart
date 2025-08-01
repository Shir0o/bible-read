import 'package:flutter/material.dart';

import '../models/group_schedule.dart';

/// List tile displaying a group's reading assignment for a single day.
class ScheduleItemTile extends StatelessWidget {
  /// Schedule entry to display.
  final GroupSchedule schedule;

  /// Callback when the edit button is tapped.
  final VoidCallback? onEdit;

  /// Creates a [ScheduleItemTile].
  const ScheduleItemTile({
    super.key,
    required this.schedule,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final dateString = schedule.date.toIso8601String().split('T').first;
    return ListTile(
      title: Text(dateString),
      subtitle: Text(schedule.chapters.join(', ')),
      trailing: onEdit == null
          ? null
          : IconButton(
              icon: const Icon(Icons.edit),
              onPressed: onEdit,
            ),
    );
  }
}

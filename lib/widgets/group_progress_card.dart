import 'package:flutter/material.dart';
import '../models/group_member_progress.dart';
import '../models/group_schedule.dart';
import '../services/group_service.dart';

/// A card that displays the overall progress of a reading group.
class GroupProgressCard extends StatelessWidget {
  final String groupId;
  final List<GroupSchedule> schedule;
  final GroupService groupService;
  final DateTime currentDate;

  const GroupProgressCard({
    super.key,
    required this.groupId,
    required this.schedule,
    required this.groupService,
    required this.currentDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Calculate time-based expected progress
    int totalChapters = 0;
    int expectedCompletedChapters = 0;
    final today =
        DateTime(currentDate.year, currentDate.month, currentDate.day);

    String? currentBook;

    for (var s in schedule) {
      totalChapters += s.chapters.length;
      if (s.date.isBefore(today) || s.date.isAtSameMomentAs(today)) {
        expectedCompletedChapters += s.chapters.length;
      }
      if (s.date.isAtSameMomentAs(today) && s.chapters.isNotEmpty) {
        // Simple parsing: assuming format "Book Chapter"
        final firstChapter = s.chapters.first;
        final parts = firstChapter.split(' ');
        if (parts.length > 1) {
          // Handle "1 John" cases
          if (int.tryParse(parts[0]) != null && parts.length > 2) {
            currentBook = '${parts[0]} ${parts[1]}';
          } else {
            currentBook = parts[0];
          }
        } else {
          currentBook = parts[0];
        }
      }
    }

    final timePercent =
        totalChapters > 0 ? expectedCompletedChapters / totalChapters : 0.0;

    return StreamBuilder<List<GroupMemberProgressData>>(
      stream: groupService.memberOverallCompletion(groupId),
      builder: (context, snapshot) {
        final members = snapshot.data ?? [];
        final double actualPercent = members.isEmpty
            ? 0.0
            : members.map((m) => m.completion).reduce((a, b) => a + b) /
                members.length;

        final percentDisplay = (actualPercent * 100).round();
        final bool isOnTrack = actualPercent >= timePercent;

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GROUP PROGRESS',
                        style: theme.textTheme.labelSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$percentDisplay%',
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isOnTrack
                          ? colorScheme.primaryContainer
                          : colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isOnTrack ? 'On Track' : 'Behind',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isOnTrack
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: actualPercent,
                  minHeight: 16,
                  backgroundColor:
                      colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(colorScheme.primary),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                currentBook != null
                    ? 'The group is $percentDisplay% through the Book of $currentBook.'
                    : 'The group is $percentDisplay% through the reading plan.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        );
      },
    );
  }
}

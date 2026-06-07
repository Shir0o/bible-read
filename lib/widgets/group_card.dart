import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

import '../models/group.dart';
import '../models/group_member_progress.dart';
import '../services/group_service.dart';
import 'member_presence_stack.dart';

class GroupCard extends StatelessWidget {
  final Group group;
  final GroupService groupService;
  final VoidCallback onTap;

  /// Opens the group's reading schedule directly (issue #721). When provided,
  /// a "View schedule" affordance is shown so the schedule is reachable without
  /// going through the group's Edit flow.
  final VoidCallback? onViewSchedule;

  const GroupCard({
    super.key,
    required this.group,
    required this.groupService,
    required this.onTap,
    this.onViewSchedule,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return StreamBuilder<List<GroupMemberProgressData>>(
      stream: groupService.memberOverallCompletion(group.id),
      builder: (context, snapshot) {
        final members = snapshot.data ?? [];
        final double groupCompletion = members.isEmpty
            ? 0.0
            : members.map((m) => m.completion).reduce((a, b) => a + b) /
                members.length;

        return FutureBuilder<List<String>>(
          future: groupService.fetchTodaysChapters(group.id),
          builder: (context, chapterSnap) {
            final chapters = chapterSnap.data ?? [];
            final String readingText = chapters.isEmpty
                ? 'No reading today'
                : 'Reading: ${chapters.join(", ")}';
            final String dailyGoalText = chapters.isEmpty
                ? 'No Daily Goal'
                : 'Daily Goal: Read ${chapters.length} ${chapters.length == 1 ? "Chapter" : "Chapters"}';

            return Semantics(
              label:
                  'Group ${group.name}, $readingText, ${(groupCompletion * 100).toInt()}% complete',
              button: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Material(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.3,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.rCard),
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.1),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      group.name,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      readingText,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${(groupCompletion * 100).toInt()}%',
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(color: colorScheme.primary),
                                  ),
                                  Text(
                                    'Group Goal',
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Progress Bar
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: groupCompletion,
                              minHeight: 8,
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Footer
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                dailyGoalText,
                                style: theme.textTheme.labelSmall,
                              ),
                              // Member Stack
                              MemberPresenceStack(members: members),
                            ],
                          ),
                          if (onViewSchedule != null) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: onViewSchedule,
                                icon: Icon(
                                  Icons.calendar_today_outlined,
                                  size: 16,
                                  color: colorScheme.primary,
                                ),
                                label: Text(
                                  'View schedule',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

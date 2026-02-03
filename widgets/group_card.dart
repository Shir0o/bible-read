import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_member_progress.dart';
import '../services/group_service.dart';
import 'common_styles.dart';

class GroupCard extends StatelessWidget {
  final Group group;
  final GroupService groupService;
  final VoidCallback onTap;

  const GroupCard({
    super.key,
    required this.group,
    required this.groupService,
    required this.onTap,
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

            return GestureDetector(
              onTap: onTap,
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.1),
                  ),
                ),
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
                                style: AppTextStyles.title.copyWith(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                readingText,
                                style: AppTextStyles.body.copyWith(
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
                              style: AppTextStyles.title.copyWith(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Group Goal',
                              style: AppTextStyles.body.copyWith(
                                fontSize: 10,
                                color: colorScheme.onSurfaceVariant,
                              ),
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
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(colorScheme.primary),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Footer
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          dailyGoalText,
                          style: AppTextStyles.body.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        // Member Stack
                        _buildMemberStack(context, members),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMemberStack(
      BuildContext context, List<GroupMemberProgressData> members) {
    if (members.isEmpty) return const SizedBox.shrink();

    // Take top 3 + remainder
    final displayMembers = members.take(3).toList();
    final remainder = members.length - 3;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      height: 32,
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
           // We need to render them in reverse order so the first one is on top
           // But Stack paints bottom-up.
           // If we want [1][2][3], and 1 overlaps 2...
           // Actually, standard stacks usually have the last item on top.
           // The design shows: Leftmost is on top? Or Rightmost?
           // Design: [1] [2] [3] [+4]
           // It looks like [1] is fully visible, [2] is behind [1]?
           // No, usually subsequent items overlap previous ones in Stacks.
           // In design: 1 overlaps 2? No, 2 overlaps 1.
           // Actually, let's look at the image.
           // User 1 is leftmost. User 2 is to the right of User 1, overlapping User 1?
           // No, usually it's `Flex` with negative margin.
           
           Row(
             mainAxisSize: MainAxisSize.min,
             children: [
               for (int i = 0; i < displayMembers.length; i++)
                 Align(
                   widthFactor: 0.7, // Overlap
                   alignment: Alignment.centerLeft,
                   child: _buildAvatar(context, displayMembers[i]),
                 ),
               if (remainder > 0)
                 Align(
                   widthFactor: 1.0, // Last one doesn't need to overlap next
                   alignment: Alignment.centerLeft,
                   child: Container(
                     width: 32,
                     height: 32,
                     decoration: BoxDecoration(
                       shape: BoxShape.circle,
                       color: colorScheme.surfaceContainerHighest,
                       border: Border.all(color: colorScheme.surface, width: 2),
                     ),
                     alignment: Alignment.center,
                     child: Text(
                       '+$remainder',
                       style: TextStyle(
                         fontSize: 10,
                         fontWeight: FontWeight.bold,
                         color: colorScheme.onSurfaceVariant,
                       ),
                     ),
                   ),
                 ),
             ],
           ),
        ],
      ),
    );
  }
  
  Widget _buildAvatar(BuildContext context, GroupMemberProgressData member) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDone = member.completion >= 1.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.surfaceContainerHighest,
            border: Border.all(color: colorScheme.surface, width: 2),
            image: member.photoUrl != null
                ? DecorationImage(
                    image: CachedNetworkImageProvider(member.photoUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: member.photoUrl == null
              ? Center(
                  child: Text(
                    member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : null,
        ),
        if (isDone)
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.surface, width: 1.5),
              ),
              child: const Icon(Icons.check, size: 8, color: Colors.white),
            ),
          ),
      ],
    );
  }
}

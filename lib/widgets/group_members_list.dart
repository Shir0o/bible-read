import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/group_member_progress.dart';
import '../services/group_service.dart';

/// A list of members in a reading group with their completion status for a specific date.
class GroupMembersList extends StatelessWidget {
  final String groupId;
  final GroupService groupService;
  final DateTime currentDate;

  const GroupMembersList({
    super.key,
    required this.groupId,
    required this.groupService,
    required this.currentDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Members',
              style: theme.textTheme.titleMedium,
            ),
            StreamBuilder<List<GroupMemberProgressData>>(
              stream: groupService.memberDailyCompletion(
                groupId,
                date: currentDate,
              ),
              builder: (context, snapshot) {
                final count = snapshot.data?.length ?? 0;
                return Text(
                  '$count Members',
                  style: theme.textTheme.labelSmall,
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: StreamBuilder<List<GroupMemberProgressData>>(
            stream: groupService.memberDailyCompletion(
              groupId,
              date: currentDate,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Failed to load members'));
              }
              if (!snapshot.hasData) {
                return const Center(
                    child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator()));
              }
              final members = snapshot.data!;
              if (members.isEmpty) {
                return const Padding(
                    padding: EdgeInsets.all(16), child: Text('No members'));
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: members.length,
                separatorBuilder: (context, index) => Divider(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  final member = members[index];
                  final isRead = member.completion >= 1.0;
                  final statusText = isRead ? 'Read today' : 'Not yet';

                  return Semantics(
                    label: '${member.name}, $statusText',
                    container: true,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: ClipOval(
                              child: member.photoUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: member.photoUrl!,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) =>
                                          const Icon(Icons.person),
                                      errorWidget: (context, url, error) =>
                                          const Icon(Icons.person),
                                    )
                                  : const Icon(Icons.person),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Semantics(
                              excludeSemantics: true,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    member.name,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w500,
                                      color: isRead
                                          ? colorScheme.onSurface
                                          : colorScheme.onSurface
                                              .withValues(alpha: 0.8),
                                    ),
                                  ),
                                  Text(
                                    statusText,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: isRead
                                          ? colorScheme.primary
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Tooltip(
                            message: isRead
                                ? 'Completed reading for today'
                                : 'Has not read today',
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isRead
                                    ? colorScheme.primary.withValues(alpha: 0.2)
                                    : Colors.transparent,
                                border: isRead
                                    ? null
                                    : Border.all(
                                        color: colorScheme.outline
                                            .withValues(alpha: 0.3),
                                      ),
                              ),
                              child: Center(
                                child: Icon(
                                  isRead ? Icons.check : Icons.hourglass_empty,
                                  size: 18,
                                  color: isRead
                                      ? colorScheme.primary
                                      : colorScheme.outline
                                          .withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

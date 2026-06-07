import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

import '../models/group.dart';
import '../models/group_member_progress.dart';
import '../services/group_service.dart';
import 'common_styles.dart';

class FindGroupCard extends StatefulWidget {
  final Group group;
  final GroupService groupService;
  final VoidCallback onJoin;

  const FindGroupCard({
    super.key,
    required this.group,
    required this.groupService,
    required this.onJoin,
  });

  @override
  State<FindGroupCard> createState() => _FindGroupCardState();
}

class _FindGroupCardState extends State<FindGroupCard> {
  late Future<List<GroupMemberProgressData>> _membersFuture;
  late Future<List<String>> _chaptersFuture;

  @override
  void initState() {
    super.initState();
    _membersFuture = widget.groupService.getGroupMembersBasic(widget.group.id);
    _chaptersFuture = widget.groupService.fetchTodaysChapters(widget.group.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.group.name,
                style: AppTextStyles.title(
                  context,
                ).copyWith(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              FutureBuilder<List<String>>(
                future: _chaptersFuture,
                builder: (context, snapshot) {
                  final chapters = snapshot.data ?? [];
                  String readingText;
                  if (chapters.isNotEmpty) {
                    final first = chapters.first;
                    // Simply show the first chapter reference or similar
                    readingText = first;
                    // If multiple chapters, maybe add "..."
                    if (chapters.length > 1) {
                      readingText += '...';
                    }
                  } else {
                    readingText = 'Bible Reading Group';
                  }

                  return Text(
                    readingText,
                    style: AppTextStyles.body(context).copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Footer with avatars and join button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Avatars
              FutureBuilder<List<GroupMemberProgressData>>(
                future: _membersFuture,
                builder: (context, snapshot) {
                  final members = snapshot.data ?? [];
                  if (members.isEmpty) {
                    if (widget.group.memberCount > 0) {
                      return Text(
                        '${widget.group.memberCount} members',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }
                  return _buildMemberStack(
                    context,
                    members,
                    widget.group.memberCount,
                  );
                },
              ),
              // Join Button
              FilledButton(
                onPressed: widget.onJoin,
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                ),
                child: const Text(
                  'Join Group',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMemberStack(
    BuildContext context,
    List<GroupMemberProgressData> members,
    int totalCount,
  ) {
    final displayMembers = members.take(3).toList();
    final remainder = totalCount > 3 ? totalCount - 3 : 0;

    final double avatarSize = 32.0;
    final double overlap = 12.0;

    final int itemCount = displayMembers.length + (remainder > 0 ? 1 : 0);
    final double width =
        avatarSize + ((itemCount - 1) * (avatarSize - overlap));

    return SizedBox(
      height: avatarSize,
      width: width,
      child: Stack(
        children: [
          for (int i = 0; i < displayMembers.length; i++)
            Positioned(
              left: i * (avatarSize - overlap),
              child: _buildAvatar(context, displayMembers[i], avatarSize),
            ),
          if (remainder > 0)
            Positioned(
              left: displayMembers.length * (avatarSize - overlap),
              child: _buildCountBubble(context, remainder, avatarSize),
            ),
        ],
      ),
    );
  }

  Widget _buildAvatar(
    BuildContext context,
    GroupMemberProgressData member,
    double size,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.surfaceContainerHighest,
        border: Border.all(color: colorScheme.surfaceContainer, width: 2),
        image: member.photoUrl != null
            ? DecorationImage(
                image: CachedNetworkImageProvider(member.photoUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: member.photoUrl == null
          ? Text(
              member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            )
          : null,
    );
  }

  Widget _buildCountBubble(BuildContext context, int count, double size) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.surfaceContainer, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '+$count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

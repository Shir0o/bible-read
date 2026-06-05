import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/group_member_progress.dart';
import '../theme/app_theme.dart';

/// Overlapping stack of member avatars — shared "who's here" presence UI used
/// by group cards and the "with your group" reading anchor (issue #721).
///
/// Shows up to [max] avatars followed by a "+N" chip. When [showDoneBadge] is
/// true, members who have finished (completion >= 1) get a small success check.
class MemberPresenceStack extends StatelessWidget {
  /// Members to display, in priority order (first shown leftmost / on top).
  final List<GroupMemberProgressData> members;

  /// Diameter of each avatar.
  final double size;

  /// Maximum number of avatars before collapsing into a "+N" chip.
  final int max;

  /// Whether to overlay a success check on finished members.
  final bool showDoneBadge;

  const MemberPresenceStack({
    super.key,
    required this.members,
    this.size = 32,
    this.max = 3,
    this.showDoneBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final displayMembers = members.take(max).toList();
    final remainder = members.length - displayMembers.length;

    return SizedBox(
      height: size,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final member in displayMembers)
            Align(
              widthFactor: 0.7, // Overlap
              alignment: Alignment.centerLeft,
              child: _buildAvatar(context, member),
            ),
          if (remainder > 0)
            Align(
              widthFactor: 1.0,
              alignment: Alignment.centerLeft,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.surfaceContainerHighest,
                  border: Border.all(color: colorScheme.surface, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$remainder',
                  style: TextStyle(
                    fontSize: size * 0.31,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, GroupMemberProgressData member) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDone = member.completion >= 1.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
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
                      fontSize: size * 0.375,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : null,
        ),
        if (showDoneBadge && isDone)
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              width: size * 0.4375,
              height: size * 0.4375,
              decoration: BoxDecoration(
                color: AppTheme.successColor(colorScheme),
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.surface, width: 1.5),
              ),
              child: Icon(
                Icons.check,
                size: size * 0.25,
                color: AppTheme.onSuccessColor(colorScheme),
              ),
            ),
          ),
      ],
    );
  }
}

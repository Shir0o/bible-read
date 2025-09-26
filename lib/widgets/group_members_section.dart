import 'package:flutter/material.dart';

import '../models/group_member_progress.dart';
import 'common_styles.dart';
import 'section_header.dart';
import 'group_member_progress.dart';

/// Displays the list of members for a group.
class GroupMembersSection extends StatelessWidget {
  /// Stream of member progress values.
  final Stream<List<GroupMemberProgressData>> membersStream;

  /// Current user's UID to enable checkbox on their row.
  final String? currentUid;

  /// Callback to toggle today's read status for current user.
  final ValueChanged<bool>? onToggleCurrentUserRead;

  const GroupMembersSection({
    super.key,
    required this.membersStream,
    this.currentUid,
    this.onToggleCurrentUserRead,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Members'),
        StreamBuilder<List<GroupMemberProgressData>>(
          stream: membersStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('Failed to load members');
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final members = snapshot.data!;
            if (members.isEmpty) {
              return const Text('No members');
            }
            return Column(
              children: members.map((member) {
                final isCurrent =
                    currentUid != null && member.uid == currentUid;
                final isRead = member.completion >= 1.0;
                Widget? trailing;
                if (isCurrent) {
                  final percent =
                      (member.completion.clamp(0.0, 1.0) * 100).round();
                  trailing = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$percent%'),
                      const SizedBox(width: 8),
                      Checkbox(
                        value: isRead,
                        onChanged: (v) =>
                            onToggleCurrentUserRead?.call(v ?? false),
                      ),
                    ],
                  );
                }
                return GroupMemberProgress(
                  name: member.name,
                  completion: member.completion,
                  trailing: trailing,
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

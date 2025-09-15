import 'package:flutter/material.dart';

import '../models/group_member_progress.dart';
import 'common_styles.dart';
import 'group_member_progress.dart';

/// Displays the list of members for a group.
class GroupMembersSection extends StatelessWidget {
  /// Stream of member progress values.
  final Stream<List<GroupMemberProgressData>> membersStream;

  const GroupMembersSection({
    super.key,
    required this.membersStream,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Members', style: AppTextStyles.subtitle),
        const SizedBox(height: 8),
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
              children: members
                  .map(
                    (member) => GroupMemberProgress(
                      name: member.name,
                      completion: member.completion,
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

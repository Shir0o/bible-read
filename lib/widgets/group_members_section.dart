import 'package:flutter/material.dart';

import 'common_styles.dart';

/// Displays the list of members for a group.
class GroupMembersSection extends StatelessWidget {
  /// Stream of member names.
  final Stream<List<String>> membersStream;

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
        StreamBuilder<List<String>>(
          stream: membersStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('Failed to load members');
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final names = snapshot.data!;
            if (names.isEmpty) {
              return const Text('No members');
            }
            return Column(
              children: names.map((n) => ListTile(title: Text(n))).toList(),
            );
          },
        ),
      ],
    );
  }
}

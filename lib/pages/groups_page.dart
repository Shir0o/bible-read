import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../services/group_service.dart';
import '../widgets/common_styles.dart';
import 'group_detail_page.dart';

/// Page that lists the groups the current user belongs to.
class GroupsPage extends StatelessWidget {
  /// Service used to load groups.
  final GroupService groupService;

  /// Firebase auth instance.
  final FirebaseAuth auth;

  /// Creates a [GroupsPage].
  GroupsPage({
    super.key,
    GroupService? groupService,
    FirebaseAuth? auth,
  })  : groupService = groupService ?? GroupService(),
        auth = auth ?? FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    return Scaffold(
      appBar: CommonStyles.buildAppBar('Groups'),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: user == null
            ? const Center(child: Text('Please sign in'))
            : StreamBuilder<List<Group>>(
                stream: groupService.groupsForUser(user.uid),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(child: Text('Failed to load groups'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final groups = snapshot.data!;
                  if (groups.isEmpty) {
                    return const Center(child: Text('No groups'));
                  }
                  return ListView.separated(
                    itemCount: groups.length,
                    separatorBuilder: (_, __) => const Divider(height: 0),
                    itemBuilder: (context, index) {
                      final g = groups[index];
                      return ListTile(
                        title: Text(g.name),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => GroupDetailPage(
                                group: g,
                                groupService: groupService,
                                auth: auth,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}

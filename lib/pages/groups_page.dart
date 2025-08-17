import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../widgets/common_styles.dart';
import 'group_detail_page.dart';
import '../widgets/menu_button.dart';

/// Page that lists all groups.
class GroupsPage extends StatefulWidget {
  /// Service used to load and manage groups.
  final GroupService groupService;

  /// Firebase auth instance.
  final FirebaseAuth auth;

  /// Creates a [GroupsPage].
  GroupsPage({super.key, GroupService? groupService, FirebaseAuth? auth})
      : groupService = groupService ?? GroupService(),
        auth = auth ?? FirebaseAuth.instance;

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  bool _inProgress = false;

  Future<void> _createGroup() async {
    final controller = TextEditingController();
    final user = widget.auth.currentUser;
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create Group'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Group Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    if (user == null || name == null || name.isEmpty || !mounted) {
      controller.dispose();
      return;
    }
    setState(() => _inProgress = true);
    try {
      await widget.groupService.createGroup(ownerUid: user.uid, name: name);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Group created')));
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to create group: $e');
      }
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create group. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _inProgress = false);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
  }

  Future<void> _joinGroup() async {
    final controller = TextEditingController();
    final user = widget.auth.currentUser;
    final id = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Join Group'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Group ID'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Join'),
            ),
          ],
        );
      },
    );
    if (user == null || id == null || id.isEmpty || !mounted) {
      controller.dispose();
      return;
    }
    setState(() => _inProgress = true);
    try {
      await widget.groupService.requestJoin(
        groupId: id,
        uid: user.uid,
        name: user.displayName ?? '',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(content: Text('Join request sent')),
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to request join: $e');
      }
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to request join. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _inProgress = false);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        'Groups',
        leading: const MenuButton(),
        automaticallyImplyLeading: false,
        actions: [
          PopupMenuButton<int>(
            onSelected: (value) {
              if (value == 0 && !_inProgress) {
                _joinGroup();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<int>(value: 0, child: Text('Join group')),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: user == null
            ? const Center(child: Text('Please sign in'))
            : StreamBuilder<List<Group>>(
                stream: widget.groupService.allGroups(),
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
                  return StreamBuilder<List<Group>>(
                    stream: widget.groupService.groupsForUser(user.uid),
                    builder: (context, mySnap) {
                      final joined =
                          mySnap.data?.map((g) => g.id).toSet() ?? <String>{};
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: widget.groupService.firestore
                            .collectionGroup(GroupCollections.joinRequests)
                            .where('uid', isEqualTo: user.uid)
                            .snapshots(),
                        builder: (context, reqSnap) {
                          final pending = reqSnap.hasData
                              ? reqSnap.data!.docs
                                  .map((d) => d.reference.parent.parent?.id)
                                  .whereType<String>()
                                  .toSet()
                              : <String>{};
                          return ListView.separated(
                            itemCount: groups.length,
                            separatorBuilder: (_, __) => const Divider(height: 0),
                            itemBuilder: (context, index) {
                              final g = groups[index];
                              return ListTile(
                                title: Text(g.name),
                                trailing: joined.contains(g.id)
                                    ? const Icon(Icons.check)
                                    : pending.contains(g.id)
                                        ? const Text('Pending')
                                        : null,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => GroupDetailPage(
                                        group: g,
                                        groupService: widget.groupService,
                                        auth: widget.auth,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'groups-fab',
        onPressed: _inProgress ? null : _createGroup,
        child: const Icon(Icons.add),
      ),
    );
  }
}

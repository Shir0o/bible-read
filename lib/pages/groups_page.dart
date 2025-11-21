import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import '../models/group.dart';
import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import 'group_detail_page.dart';

/// Page that lists all groups.
class GroupsPage extends StatefulWidget {
  /// Service used to load and manage groups.
  final GroupService groupService;

  /// Firebase auth instance.
  final FirebaseAuth auth;

  /// Service used to trigger vibrations.
  final VibrationService vibrationService;

  /// Creates a [GroupsPage].
  GroupsPage({
    super.key,
    GroupService? groupService,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
  })  : groupService = groupService ?? GroupService(),
        auth = auth ?? FirebaseAuth.instance,
        vibrationService = vibrationService ?? const VibrationService();

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  bool _inProgress = false;
  int _refreshTick = 0;

  Future<void> _refresh() async {
    try {
      await widget.auth.currentUser?.reload();
      final uid = widget.auth.currentUser?.uid;
      if (uid != null) {
        // Validate and fix cached member progress for joined/owned groups.
        await widget.groupService.fixMemberProgressSummariesForUser(uid);
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _refreshTick++);
    }
  }

  Future<void> _createGroup() async {
    final controller = TextEditingController();
    var disposed = false;

    void disposeController() {
      if (disposed) {
        return;
      }
      disposed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }

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
              onPressed: () {
                unawaited(widget.vibrationService.lightImpact());
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                unawaited(widget.vibrationService.lightImpact());
                Navigator.of(context).pop(controller.text.trim());
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    if (user == null || name == null || name.isEmpty || !mounted) {
      disposeController();
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
      disposeController();
    }
  }

  Future<void> _openGroup(Group group) async {
    unawaited(widget.vibrationService.lightImpact());
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => GroupDetailPage(
          group: group,
          groupService: widget.groupService,
          auth: widget.auth,
        ),
      ),
    );
    if (!mounted || deleted != true) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Group deleted')));
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        'Groups',
        automaticallyImplyLeading: false,
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: user == null
            ? RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 200),
                    Center(child: Text('Please sign in')),
                  ],
                ),
              )
            : StreamBuilder<List<Group>>(
                key: ValueKey('all-groups-$_refreshTick'),
                stream: widget.groupService.allGroups(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 200),
                          Center(child: Text('Failed to load groups')),
                        ],
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 200),
                          Center(child: CircularProgressIndicator()),
                        ],
                      ),
                    );
                  }
                  final groups = snapshot.data!;
                  if (groups.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 200),
                          Center(child: Text('No groups')),
                        ],
                      ),
                    );
                  }
                  return StreamBuilder<List<Group>>(
                    key: ValueKey('my-groups-$_refreshTick'),
                    stream: widget.groupService.groupsForUser(user.uid),
                    builder: (context, mySnap) {
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
                          return RefreshIndicator(
                            onRefresh: _refresh,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: groups.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 0),
                              itemBuilder: (context, index) {
                                final g = groups[index];
                                return StreamBuilder<
                                    QuerySnapshot<Map<String, dynamic>>>(
                                  stream: widget.groupService.firestore
                                      .collection(GroupCollections.groups)
                                      .doc(g.id)
                                      .collection(GroupCollections.members)
                                      .snapshots(),
                                  builder: (context, memberSnap) {
                                    final docs =
                                        memberSnap.data?.docs ?? const [];
                                    final liveCount = docs.length;
                                    // Ensure the owner appears in count even if their member doc is missing.
                                    final hasOwner = docs.any((d) =>
                                        d.id == g.ownerUid ||
                                        (d.data()['uid'] as String?) ==
                                            g.ownerUid);
                                    final adjusted =
                                        hasOwner ? liveCount : liveCount + 1;
                                    final count =
                                        (memberSnap.hasData && adjusted > 0)
                                            ? adjusted
                                            : g.memberCount;
                                    return CommonStyles.buildTappableCard(
                                      onTap: () => _openGroup(g),
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 4.0),
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(g.name),
                                        subtitle: Text(
                                          '$count member${count == 1 ? '' : 's'}',
                                        ),
                                        trailing: pending.contains(g.id)
                                            ? const Text('Pending')
                                            : null,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
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

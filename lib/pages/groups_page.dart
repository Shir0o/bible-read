import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/group_card.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/skeletons/group_list_skeleton.dart';
import '../pages/group_detail_page.dart';
import '../pages/all_groups_page.dart';

class GroupsPage extends StatefulWidget {
  final GroupService groupService;
  final FirebaseAuth auth;
  final VibrationService vibrationService;

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
        return StatefulBuilder(
          builder: (context, setState) {
            final isNotEmpty = controller.text.trim().isNotEmpty;
            return AlertDialog(
              title: const Text('Create Group'),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Group Name',
                  suffixIcon: isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Clear name',
                          onPressed: () {
                            controller.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (value) {
                  if (isNotEmpty) {
                    unawaited(widget.vibrationService.lightImpact());
                    Navigator.of(context).pop(value.trim());
                  }
                },
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
                  onPressed: isNotEmpty
                      ? () {
                          unawaited(widget.vibrationService.lightImpact());
                          Navigator.of(context).pop(controller.text.trim());
                        }
                      : null,
                  child: const Text('Create'),
                ),
              ],
            );
          },
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

  void _showJoinOrCreateOptions() {
    unawaited(widget.vibrationService.lightImpact());
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('Create New Group'),
                onTap: () {
                  Navigator.pop(context);
                  _createGroup();
                },
              ),
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('Find a Group'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AllGroupsPage(
                        groupService: widget.groupService,
                        auth: widget.auth,
                        vibrationService: widget.vibrationService,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: CommonStyles.buildAppBar(context, 'My Groups'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: StreamBuilder<List<Group>>(
                  key: ValueKey('my-groups-page-$_refreshTick'),
                  stream: widget.groupService.groupsForUser(user.uid),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('Error loading groups: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final groups = snapshot.data!;
                    if (groups.isEmpty) {
                      return LayoutBuilder(
                          builder: (context, constraints) {
                            return SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Text(
                                      'You haven\'t joined any groups yet.',
                                      style: AppTextStyles.body.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: groups.length,
                      itemBuilder: (context, index) {
                        final group = groups[index];
                        return GroupCard(
                          group: group,
                          groupService: widget.groupService,
                          onTap: () => _openGroup(group),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            // Bottom Button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _showJoinOrCreateOptions,
                  icon: const Icon(Icons.add_circle, size: 20),
                  label: const Text('Join or Create Group'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

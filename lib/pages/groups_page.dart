import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

import '../models/group.dart';
import '../models/group_invite.dart';

import '../services/group_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/group_card.dart';
import '../widgets/skeletons/group_list_skeleton.dart';

import '../pages/group_detail_page.dart';
import '../pages/all_groups_page.dart';
import '../pages/create_group_page.dart';
import '../pages/full_schedule_page.dart';

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
  int _refreshTick = 0;
  bool _isSyncing = false;

  Future<void> _refresh() async {
    try {
      await widget.auth.currentUser?.reload();
    } catch (_) {}
    if (mounted) {
      setState(() => _refreshTick++);
    }
  }

  Future<void> _syncGroups() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null || _isSyncing) return;

    setState(() => _isSyncing = true);
    unawaited(widget.vibrationService.lightImpact());

    try {
      await widget.groupService.fixMemberProgressSummariesForUser(uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group progress synchronized')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to synchronize groups')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _refreshTick++;
        });
      }
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Group deleted')));
  }

  void _openSchedule(Group group) {
    unawaited(widget.vibrationService.lightImpact());
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FullSchedulePage(
          group: group,
          groupService: widget.groupService,
          auth: widget.auth,
          vibrationService: widget.vibrationService,
          isMember: true,
        ),
      ),
    );
  }

  void _showJoinOrCreateOptions() {
    unawaited(widget.vibrationService.lightImpact());
    showModalBottomSheet(
      context: context,
      barrierColor: AppColors.of(context).scrim,
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CreateGroupPage(
                        groupService: widget.groupService,
                        auth: widget.auth,
                        vibrationService: widget.vibrationService,
                      ),
                    ),
                  );
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
      appBar: CommonStyles.buildAppBar(
        context,
        'My Groups',
        actions: [
          _isSyncing
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                )
              : IconButton(
                  tooltip: 'Sync groups',
                  icon: const Icon(Icons.sync),
                  onPressed: _syncGroups,
                ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: StreamBuilder<List<GroupInvite>>(
                  stream: widget.groupService.userInvites(user.uid),
                  builder: (context, inviteSnapshot) {
                    final invites = inviteSnapshot.data ?? [];

                    return StreamBuilder<List<Group>>(
                      key: ValueKey('my-groups-page-$_refreshTick'),
                      stream: widget.groupService.groupsForUser(user.uid),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'Error loading groups: ${snapshot.error}',
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const GroupListSkeleton();
                        }
                        final groups = snapshot.data!;

                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (invites.isNotEmpty) ...[
                              _buildInvitesSection(context, invites),
                              const SizedBox(height: 24),
                            ],
                            if (groups.isEmpty && invites.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  'You haven\'t joined any groups yet.',
                                  style: AppTextStyles.body(context).copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            else
                              ...groups.map(
                                (group) => GroupCard(
                                  group: group,
                                  groupService: widget.groupService,
                                  onTap: () => _openGroup(group),
                                  onViewSchedule: () => _openSchedule(group),
                                ),
                              ),
                          ],
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
                    textStyle: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 16,
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

  Widget _buildInvitesSection(BuildContext context, List<GroupInvite> invites) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'INVITATIONS',
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.2,
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        ...invites.map(
          (invite) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 0,
            color: AppColors.of(context).primarySoft,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.of(context).primaryLine),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invite.groupName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Invited by ${invite.senderName}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.check_circle_outline),
                    color: colorScheme.primary,
                    onPressed: () async {
                      final user = widget.auth.currentUser;
                      if (user == null) return;
                      try {
                        await widget.groupService.respondToGroupInvite(
                          groupId: invite.groupId,
                          uid: user.uid,
                          name: user.displayName ?? '',
                          photoUrl: user.photoURL,
                          accept: true,
                        );
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Failed to accept invitation'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel_outlined),
                    color: colorScheme.error,
                    onPressed: () async {
                      final user = widget.auth.currentUser;
                      if (user == null) return;
                      try {
                        await widget.groupService.respondToGroupInvite(
                          groupId: invite.groupId,
                          uid: user.uid,
                          name: user.displayName ?? '',
                          accept: false,
                        );
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Failed to decline invitation'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

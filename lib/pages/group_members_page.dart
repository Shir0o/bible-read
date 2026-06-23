import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

import '../models/group.dart';
import '../models/group_invite.dart';
import '../models/group_member_progress.dart';
import '../models/group_member_role.dart';
import '../services/error_logger.dart';
import '../services/friend_service.dart';
import '../services/group_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/nudge_sheet.dart';

/// Roster management for a reading group: roles, per-member read status,
/// nudge, promote / transfer ownership / remove, and pending invites.
class GroupMembersPage extends StatefulWidget {
  /// The group whose members are being managed.
  final Group group;

  /// Service for group operations.
  final GroupService groupService;

  /// Service used to send nudges.
  final FriendService friendService;

  /// Authentication used to identify the current user.
  final FirebaseAuth auth;

  /// Haptics service.
  final VibrationService vibrationService;

  /// Date used to compute today's read status.
  final DateTime? currentDate;

  /// Creates a [GroupMembersPage].
  const GroupMembersPage({
    super.key,
    required this.group,
    required this.groupService,
    required this.friendService,
    required this.auth,
    required this.vibrationService,
    this.currentDate,
  });

  @override
  State<GroupMembersPage> createState() => _GroupMembersPageState();
}

class _GroupMembersPageState extends State<GroupMembersPage> {
  late final DateTime _date;

  @override
  void initState() {
    super.initState();
    _date = widget.currentDate ?? DateTime.now();
  }

  String? get _myUid => widget.auth.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar(context, 'Members'),
      body: Container(
        decoration: CommonStyles.backgroundDecoration(
          Theme.of(context).colorScheme,
        ),
        child: StreamBuilder<List<GroupMemberRole>>(
          stream: widget.groupService.membersWithRoles(widget.group.id),
          builder: (context, rolesSnap) {
            if (rolesSnap.hasError) {
              return const Center(child: Text('Failed to load members'));
            }
            if (!rolesSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final roster = rolesSnap.data!;
            return StreamBuilder<List<GroupMemberProgressData>>(
              stream: widget.groupService.memberDailyCompletion(
                widget.group.id,
                date: _date,
              ),
              builder: (context, readSnap) {
                final readByUid = <String, double>{
                  for (final m in readSnap.data ?? <GroupMemberProgressData>[])
                    m.uid: m.completion,
                };
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildRoster(roster, readByUid),
                    const SizedBox(height: 20),
                    _buildPendingInvites(roster),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant, width: 0.5),
      ),
      child: child,
    );
  }

  String _myRole(List<GroupMemberRole> roster) {
    if (_myUid == widget.group.ownerUid) return 'owner';
    final me = roster.where((m) => m.uid == _myUid).firstOrNull;
    return me?.role ?? 'member';
  }

  Widget _buildRoster(
    List<GroupMemberRole> roster,
    Map<String, double> readByUid,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final myRole = _myRole(roster);
    final readCount =
        roster.where((m) => (readByUid[m.uid] ?? 0) >= 1.0).length;

    // Sort: roles already sorted by service; pull "me" to the top within rank.
    final sorted = [...roster]..sort((a, b) {
        final byRole = a.roleRank.compareTo(b.roleRank);
        if (byRole != 0) return byRole;
        if (a.uid == _myUid) return -1;
        if (b.uid == _myUid) return 1;
        return 0;
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Members · ${roster.length}',
                style: theme.textTheme.titleMedium),
            Row(
              children: [
                Icon(Icons.menu_book_outlined,
                    size: 15, color: colorScheme.primary),
                const SizedBox(width: 5),
                Text(
                  '$readCount read today',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        _card(
          child: Column(
            children: [
              for (var i = 0; i < sorted.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    color: AppColors.of(context).border,
                  ),
                _buildMemberRow(
                  sorted[i],
                  (readByUid[sorted[i].uid] ?? 0) >= 1.0,
                  myRole,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMemberRow(GroupMemberRole member, bool isRead, String myRole) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMe = member.uid == _myUid;
    final canManage = myRole == 'owner' || myRole == 'admin';
    // Admins can only manage plain members; owner can manage anyone but self.
    final manageable =
        canManage && !isMe && !(myRole == 'admin' && member.role != 'member');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          _MemberAvatar(
            name: member.name,
            photoUrl: member.photoUrl,
            size: 38,
            read: isRead,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isMe ? 'You' : (member.name ?? 'Member'),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    RoleBadge(role: member.role),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  isRead ? 'Read today' : 'Not yet today',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isRead
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!isMe && !isRead) _NudgeChip(onTap: () => _nudge(member)),
          if (manageable)
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Manage ${member.name ?? 'member'}',
              onPressed: () => _openActionSheet(member, myRole),
            ),
        ],
      ),
    );
  }

  Widget _buildPendingInvites(List<GroupMemberRole> roster) {
    final myRole = _myRole(roster);
    final canManage = myRole == 'owner' || myRole == 'admin';
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return StreamBuilder<List<GroupInvite>>(
      stream: widget.groupService.pendingInvites(widget.group.id),
      builder: (context, snap) {
        final invites = snap.data ?? <GroupInvite>[];
        if (invites.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pending · ${invites.length}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                )),
            const SizedBox(height: 10),
            _card(
              child: Column(
                children: [
                  for (var i = 0; i < invites.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        color: AppColors.of(context).border,
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      child: Row(
                        children: [
                          _MemberAvatar(
                            name: null,
                            photoUrl: null,
                            size: 36,
                            read: false,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              invites[i].recipientUid,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          if (canManage)
                            TextButton(
                              onPressed: () => _cancelInvite(invites[i]),
                              child: const Text('Cancel'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _nudge(GroupMemberRole member) async {
    final me = widget.auth.currentUser;
    if (me == null) return;
    unawaited(widget.vibrationService.lightImpact());
    await showNudgeSheet(
      context,
      person:
          NudgePerson(name: member.name ?? 'Friend', photoUrl: member.photoUrl),
      vibrationService: widget.vibrationService,
      onSend: (message) async {
        try {
          return await widget.friendService.nudgeFriend(
            currentUid: me.uid,
            friendUid: member.uid,
            currentName: me.displayName ?? 'You',
          );
        } catch (e, st) {
          ErrorLogger.log(e, st);
          rethrow;
        }
      },
    );
  }

  Future<void> _cancelInvite(GroupInvite invite) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.groupService.cancelInvite(
        groupId: widget.group.id,
        inviteeUid: invite.recipientUid,
      );
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn’t cancel the invite')),
      );
    }
  }

  void _openActionSheet(GroupMemberRole member, String myRole) {
    showModalBottomSheet<void>(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        final theme = Theme.of(sheetContext);
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _MemberAvatar(
                      name: member.name,
                      photoUrl: member.photoUrl,
                      size: 46,
                      read: false,
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(member.name ?? 'Member',
                              style: theme.textTheme.titleMedium),
                          Text(
                            _roleLabel(member.role),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _ActionRow(
                  icon: Icons.waving_hand_outlined,
                  label: 'Send a nudge',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _nudge(member);
                  },
                ),
                if (myRole == 'owner' && member.role == 'member')
                  _ActionRow(
                    icon: Icons.shield_outlined,
                    label: 'Make admin',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _promote(member);
                    },
                  ),
                if (myRole == 'owner' && member.role == 'admin')
                  _ActionRow(
                    icon: Icons.remove_moderator_outlined,
                    label: 'Remove admin role',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _demote(member);
                    },
                  ),
                if (myRole == 'owner')
                  _ActionRow(
                    icon: Icons.workspace_premium_outlined,
                    label: 'Transfer ownership',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _confirmTransfer(member);
                    },
                  ),
                _ActionRow(
                  icon: Icons.person_remove_outlined,
                  label: 'Remove from group',
                  danger: true,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _confirmRemove(member);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _promote(GroupMemberRole member) async {
    await _run(() => widget.groupService.promoteToAdmin(
          groupId: widget.group.id,
          ownerUid: widget.group.ownerUid,
          uid: member.uid,
        ));
  }

  Future<void> _demote(GroupMemberRole member) async {
    await _run(() => widget.groupService.demoteAdmin(
          groupId: widget.group.id,
          ownerUid: widget.group.ownerUid,
          uid: member.uid,
        ));
  }

  Future<void> _confirmTransfer(GroupMemberRole member) async {
    final me = _myUid;
    if (me == null) return;
    final ok = await _confirm(
      title: 'Transfer ownership?',
      body: '${member.name ?? 'This member'} will become the owner and you’ll '
          'become an admin. This can’t be undone by you alone.',
      confirmLabel: 'Transfer',
    );
    if (ok != true) return;
    await _run(() => widget.groupService.transferOwnership(
          groupId: widget.group.id,
          currentOwnerUid: me,
          newOwnerUid: member.uid,
        ));
  }

  Future<void> _confirmRemove(GroupMemberRole member) async {
    final ok = await _confirm(
      title: 'Remove member?',
      body: '${member.name ?? 'This member'} will be removed from the group.',
      confirmLabel: 'Remove',
      danger: true,
    );
    if (ok != true) return;
    await _run(() => widget.groupService.kickMember(
          groupId: widget.group.id,
          uid: member.uid,
        ));
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: danger
                ? TextButton.styleFrom(
                    foregroundColor: Theme.of(dialogContext).colorScheme.error,
                  )
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Something went wrong. Please try again.')),
      );
    }
  }

  String _roleLabel(String role) => switch (role) {
        'owner' => 'Owner',
        'admin' => 'Admin',
        _ => 'Member',
      };
}

/// A small badge indicating a member's role. Renders nothing for plain members.
class RoleBadge extends StatelessWidget {
  /// The member's role.
  final String role;

  /// Creates a [RoleBadge].
  const RoleBadge({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    if (role == 'member') return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    final isOwner = role == 'owner';
    final color = isOwner ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
      decoration: BoxDecoration(
        color: isOwner
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOwner ? Icons.workspace_premium : Icons.shield_outlined,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isOwner ? 'OWNER' : 'ADMIN',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _NudgeChip extends StatelessWidget {
  const _NudgeChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ActionChip(
      onPressed: onTap,
      avatar: Icon(Icons.waving_hand_outlined,
          size: 15, color: colorScheme.primary),
      label: const Text('Nudge'),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: colorScheme.primary,
      ),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: colorScheme.outlineVariant),
      backgroundColor: colorScheme.surface,
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = danger ? colorScheme.error : colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon,
                    size: 19,
                    color: danger ? colorScheme.error : colorScheme.primary),
                const SizedBox(width: 13),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({
    required this.name,
    required this.photoUrl,
    required this.size,
    required this.read,
  });

  final String? name;
  final String? photoUrl;
  final double size;
  final bool read;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: read ? colorScheme.primary : colorScheme.outlineVariant,
          width: read ? 2 : 1,
        ),
      ),
      child: ClipOval(
        child: photoUrl != null
            ? CachedNetworkImage(
                imageUrl: photoUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Icon(Icons.person),
                errorWidget: (context, url, error) => const Icon(Icons.person),
              )
            : Icon(Icons.person, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

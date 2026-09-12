import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_schedule.dart';
import '../services/catch_up_engine.dart';
import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../services/plan_pace_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/sub_header.dart';
import 'reschedule_page.dart';

/// Group settings: name, visibility, Reschedule, and lifecycle actions.
///
/// The plan editor that used to live here is retired. Adjust pace is the
/// personal answer and stays on the Path card; Reschedule is the owner-only
/// group-wide move and lives on this page.
class EditGroupPage extends StatefulWidget {
  final Group group;
  final GroupService groupService;
  final FirebaseAuth auth;
  final VibrationService vibrationService;
  final DateTime Function()? dateProvider;

  const EditGroupPage({
    super.key,
    required this.group,
    required this.groupService,
    required this.auth,
    this.vibrationService = const VibrationService(),
    this.dateProvider,
  });

  @override
  State<EditGroupPage> createState() => _EditGroupPageState();
}

class _EditGroupPageState extends State<EditGroupPage> {
  bool _isLoading = true;
  bool _isSaving = false;

  late bool _isPublic;
  late final TextEditingController _nameController;

  List<GroupSchedule> _schedule = const [];
  Set<String> _completedDateIds = const {};
  int _daysBehind = 0;

  @override
  void initState() {
    super.initState();
    _isPublic = widget.group.isPublic;
    _nameController = TextEditingController(text: widget.group.name);
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _isOwner => widget.auth.currentUser?.uid == widget.group.ownerUid;

  Future<void> _loadData() async {
    try {
      final schedule =
          await widget.groupService.schedule(widget.group.id).first;
      final uid = widget.auth.currentUser?.uid;
      var completed = <String>{};
      if (uid != null) {
        final progress = await widget.groupService
            .userProgressForGroup(widget.group.id, uid)
            .first;
        completed = progress.entries
            .where((entry) => entry.value > 0)
            .map((entry) => entry.key)
            .toSet();
      }
      final today = widget.dateProvider?.call() ?? DateTime.now();
      final status = CatchUpEngine.forGroupSchedule(
        schedule,
        completed,
        today: today,
      );
      if (mounted) {
        setState(() {
          _schedule = schedule;
          _completedDateIds = completed;
          _daysBehind = status.missedCount;
          _isLoading = false;
        });
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load group settings')),
        );
      }
    }
  }

  Future<void> _saveChanges() async {
    if (_isSaving || _isOwner == false) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please name your group.')),
      );
      return;
    }
    setState(() => _isSaving = true);
    unawaited(widget.vibrationService.lightImpact());
    try {
      if (name != widget.group.name) {
        await widget.groupService.updateGroupName(
          groupId: widget.group.id,
          name: name,
        );
      }
      if (_isPublic != widget.group.isPublic) {
        await widget.groupService.updateGroupPublicStatus(
          groupId: widget.group.id,
          isPublic: _isPublic,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group settings saved')),
        );
        Navigator.pop(context, true);
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save group settings')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _openReschedule() async {
    if (_isOwner == false) return;
    unawaited(widget.vibrationService.lightImpact());
    final today = widget.dateProvider?.call() ?? DateTime.now();
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReschedulePage(
          group: widget.group,
          groupService: widget.groupService,
          paceService:
              PlanPaceService(firestore: widget.groupService.firestore),
          auth: widget.auth,
          schedule: _schedule,
          completedDateIds: _completedDateIds,
          daysBehind: _daysBehind,
          today: today,
          vibrationService: widget.vibrationService,
        ),
      ),
    );
  }

  /// Owner action (#776): archives the group - shelved for every member,
  /// schedule and history intact, restorable from the hub's Archive rows.
  Future<void> _archiveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      builder: (context) => AlertDialog(
        title: const Text('Archive Group'),
        content: const Text(
          'The group is shelved for every member. Its schedule and history '
          'stay intact, and you can unarchive it any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.groupService.archiveGroup(
          groupId: widget.group.id,
          ownerUid: widget.auth.currentUser!.uid,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Group archived')),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e, st) {
        ErrorLogger.log(e, st);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to archive group')),
          );
        }
      }
    }
  }

  /// Owner action (#776): soft-deletes the group - 30 days in the Recently
  /// Deleted hub, restorable, then purged.
  Future<void> _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group'),
        content: const Text(
          'The group moves to Recently Deleted for 30 days. Members lose '
          'access until you restore it or the 30 days run out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.groupService.softDeleteGroup(
          groupId: widget.group.id,
          ownerUid: widget.auth.currentUser!.uid,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Group moved to Recently Deleted')),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e, st) {
        ErrorLogger.log(e, st);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete group')),
          );
        }
      }
    }
  }

  /// Member action (#776): archives this member's participation only - the
  /// group keeps running for everyone else.
  Future<void> _archiveParticipation() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await widget.groupService.archiveMemberParticipation(
        groupId: widget.group.id,
        uid: uid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Participation archived - find it in your Archive'),
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to archive participation')),
        );
      }
    }
  }

  /// Member action (#776): leaves the group; the group stays intact for
  /// everyone else.
  Future<void> _leaveGroup() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group'),
        content: const Text(
          'You leave this group. The group stays intact for the other '
          'members, and your reading record for it is removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.groupService.leaveGroup(
          groupId: widget.group.id,
          uid: uid,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You left the group')),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e, st) {
        ErrorLogger.log(e, st);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to leave group')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SubHeader(
              title: 'Group settings',
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionTitle(context, 'Group Settings'),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('group-settings-name'),
                      controller: _nameController,
                      enabled: _isOwner,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Group name',
                      ),
                    ),
                    const SizedBox(height: 16),
                    _publicCard(context),
                    if (_isOwner) ...[
                      const SizedBox(height: 24),
                      _sectionTitle(context, 'Schedule'),
                      const SizedBox(height: 10),
                      _rescheduleTile(context),
                    ],
                    const SizedBox(height: 28),
                    _sectionTitle(context, 'Manage group'),
                    const SizedBox(height: 10),
                    if (_isOwner) ...[
                      _lifecycleButton(
                        context,
                        icon: Icons.inventory_2,
                        label: 'Archive Group',
                        onPressed: _archiveGroup,
                      ),
                      const SizedBox(height: 12),
                      _lifecycleButton(
                        context,
                        icon: Icons.delete_outline,
                        label: 'Delete Group',
                        onPressed: _deleteGroup,
                        destructive: true,
                      ),
                    ] else ...[
                      _lifecycleButton(
                        context,
                        icon: Icons.inventory_2,
                        label: 'Archive Participation',
                        onPressed: _archiveParticipation,
                      ),
                      const SizedBox(height: 12),
                      _lifecycleButton(
                        context,
                        icon: Icons.logout,
                        label: 'Leave Group',
                        onPressed: _leaveGroup,
                        destructive: true,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _isOwner ? _saveBar(context) : null,
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _publicCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Public Group',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 18,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Visible in group search results',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isPublic,
            activeTrackColor: colorScheme.primary,
            onChanged:
                _isOwner ? (value) => setState(() => _isPublic = value) : null,
          ),
        ],
      ),
    );
  }

  Widget _rescheduleTile(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);
    return InkWell(
      onTap: _openReschedule,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border.all(color: appColors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.edit_calendar, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reschedule',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Move the dates for every member',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colorScheme.outline),
          ],
        ),
      ),
    );
  }

  Widget _lifecycleButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool destructive = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = destructive ? colorScheme.error : colorScheme.tertiary;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: color),
        label: Text(label, style: TextStyle(color: color)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withValues(alpha: 0.3)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _saveBar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: FilledButton(
        key: const Key('group-settings-save'),
        onPressed: _isSaving ? null : _saveChanges,
        child: Text(_isSaving ? 'Saving...' : 'Save changes'),
      ),
    );
  }
}

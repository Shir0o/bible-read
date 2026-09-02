import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/group.dart';
import '../models/group_member_progress.dart';
import '../models/group_plan_config.dart';
import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../services/progress_remap.dart';
import '../services/schedule_generator.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/group_plan_form.dart';
import '../widgets/group_plan_keys.dart';
import '../widgets/plan_day_list.dart';
import '../widgets/rebuild_confirm_dialog.dart';
import '../widgets/sub_header.dart';
import 'adjust_days_page.dart';

/// Edits a group's plan and members.
///
/// Adopts the shared `GroupPlanForm` so the edit screen matches the create
/// flow. The host owns persistence: it loads `planConfig` (or infers it from
/// the existing schedule for legacy groups), tracks the draft the form
/// publishes, writes the schedule + config on save, and triggers the
/// `remapGroupProgress` callable — falling back to the local
/// `applyOwnRemap` if the cloud function fails.
class EditGroupPage extends StatefulWidget {
  final Group group;
  final GroupService groupService;
  final FirebaseAuth auth;
  final VibrationService vibrationService;

  const EditGroupPage({
    super.key,
    required this.group,
    required this.groupService,
    required this.auth,
    this.vibrationService = const VibrationService(),
  });

  @override
  State<EditGroupPage> createState() => _EditGroupPageState();
}

class _EditGroupPageState extends State<EditGroupPage> {
  bool _isLoading = true;
  bool _isSaving = false;

  GroupPlanDraft _draft = GroupPlanDraft.initial();
  GeneratedPlan _plan = GeneratedPlan.empty;

  late bool _isPublic;

  List<GroupMemberProgressData> _members = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final schedule =
          await widget.groupService.schedule(widget.group.id).first;

      // planConfig is the source of truth on groups saved after this feature
      // shipped. For legacy groups (those without it), reconstruct from the
      // materialised schedule — recovering the starting chapter that the old
      // edit screen silently reset to chapter 1.
      final planConfig =
          widget.group.planConfig ?? GroupPlanDraft.inferFromSchedule(schedule);

      _draft = planConfig;
      _plan = ScheduleGenerator.planFromDraft(_draft);
      _isPublic = widget.group.isPublic;

      final members = await widget.groupService
          .memberOverallCompletion(widget.group.id)
          .first;
      _members = members;

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e, st) {
      if (mounted) {
        ErrorLogger.log(e, st);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load group data')),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _saveChanges() async {
    if (_draft.books.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one book.')),
      );
      return;
    }
    if (_plan.days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Choose an end date to work out the pace.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    unawaited(widget.vibrationService.lightImpact());

    try {
      final oldSchedule =
          await widget.groupService.schedule(widget.group.id).first;

      // Decide whether the new plan actually differs and someone has progress.
      // The remap happens regardless — progress follows chapter references —
      // but the dialog is the owner's last chance to back out.
      final oldDraft = widget.group.planConfig ??
          GroupPlanDraft.inferFromSchedule(oldSchedule);
      final allProgress = await _readAllProgress();
      final remap = remapProgress(
        oldDays: oldSchedule,
        newDays: _plan.days,
        completedByDate: allProgress,
      );

      final planChanged = _draft != oldDraft;
      final hasDrops = remap.droppedRefs.isNotEmpty;
      if (planChanged && hasDrops && mounted) {
        final confirmed = await showRebuildConfirmDialog(
          context: context,
          oldDraft: oldDraft,
          newDraft: _draft,
          newDays: _plan.days,
          remap: remap,
        );
        if (!confirmed) {
          if (mounted) setState(() => _isSaving = false);
          return;
        }
      }

      // Write the new plan before removing the days it replaces. If the write
      // fails, the group keeps its old schedule; the other order would leave
      // it with days deleted and nothing put back.
      await widget.groupService.updateScheduleBatch(
        groupId: widget.group.id,
        schedules: _plan.days,
      );

      final newDateKeys =
          _plan.days.map((s) => GroupService.dateId(s.date)).toSet();
      await widget.groupService.deleteScheduleDays(
        groupId: widget.group.id,
        dates: oldSchedule
            .where((s) => !newDateKeys.contains(GroupService.dateId(s.date)))
            .map((s) => s.date),
      );

      // Bump revision so every member's client knows their progress is stale
      // and should be re-mapped on next open.
      final nextRevision = oldDraft.revision + 1;
      await widget.groupService.updatePlanConfig(
        groupId: widget.group.id,
        config: _draft.copyWith(revision: nextRevision),
      );

      if (_isPublic != widget.group.isPublic) {
        await widget.groupService.updateGroupPublicStatus(
          groupId: widget.group.id,
          isPublic: _isPublic,
        );
      }

      // Best-effort: ask the cloud function to remap everyone's progress
      // cross-member. If it fails or is unavailable, fall back to the
      // per-member self-repair so the owner's own ticks still follow.
      final cloudOk = await widget.groupService.remapGroupProgressCallable(
        groupId: widget.group.id,
        newDays: _plan.days,
      );
      if (!cloudOk) {
        final uid = widget.auth.currentUser?.uid;
        if (uid != null) {
          await widget.groupService.applyOwnRemap(
            groupId: widget.group.id,
            uid: uid,
            oldDays: oldSchedule,
            newDays: _plan.days,
          );
          await widget.groupService.markMemberRemapped(
            groupId: widget.group.id,
            uid: uid,
            revision: nextRevision,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Group plan updated')));
        Navigator.pop(context);
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to update plan')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Reads every member's ticked indices across every progress date. Used by
  /// the rebuild dialog to phrase "X chapters of Y leave the plan" honestly.
  Future<Map<String, Map<String, Set<int>>>> _readAllProgress() async {
    final result = <String, Map<String, Set<int>>>{};
    final progressSnap = await widget.groupService.firestore
        .collection(GroupCollections.groups)
        .doc(widget.group.id)
        .collection('progress')
        .get();
    for (final dayDoc in progressSnap.docs) {
      final dateId = dayDoc.id;
      final entriesSnap = await dayDoc.reference.collection('entries').get();
      for (final entryDoc in entriesSnap.docs) {
        final uid = entryDoc.id;
        final data = entryDoc.data();
        final count = (data['count'] as num?)?.toInt() ?? 0;
        if (count > 0) {
          final itemsSnap = await entryDoc.reference.collection('items').get();
          result.putIfAbsent(uid, () => <String, Set<int>>{})[dateId] = {
            for (final item in itemsSnap.docs) int.parse(item.id),
          };
        } else if (data['done'] == true) {
          // Legacy "whole day done" — empty set means every chapter.
          result.putIfAbsent(uid, () => <String, Set<int>>{})[dateId] = <int>{};
        }
      }
    }
    return result;
  }

  Future<void> _archiveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      builder: (context) => AlertDialog(
        title: const Text('Archive Group'),
        content: const Text(
          'Are you sure you want to archive (delete) this group? This cannot be undone.',
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
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.groupService.deleteGroup(
          groupId: widget.group.id,
          ownerUid: widget.auth.currentUser!.uid,
        );
        if (mounted) {
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

  Future<void> _kickMember(String uid, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove $name from the group?'),
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.groupService.kickMember(
          groupId: widget.group.id,
          uid: uid,
        );
        setState(() {
          _members.removeWhere((m) => m.uid == uid);
        });
      } catch (e, st) {
        ErrorLogger.log(e, st);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to remove member')),
          );
        }
      }
    }
  }

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: 'Join my group: ${widget.group.id}'));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copied to clipboard')));
  }

  Future<GroupPlanDraft?> _openAdjustDays(GroupPlanDraft draft) {
    return Navigator.push<GroupPlanDraft>(
      context,
      MaterialPageRoute(
        builder: (context) => AdjustDaysPage(
          draft: draft,
          vibrationService: widget.vibrationService,
        ),
      ),
    );
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
              title: 'Edit Group Plan',
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GroupPlanForm(
                      initial: _draft,
                      vibrationService: widget.vibrationService,
                      onSeeAllDays: _openAdjustDays,
                      onChanged: (draft, plan) {
                        setState(() {
                          _draft = draft;
                          _plan = plan;
                        });
                      },
                    ),
                    const SizedBox(height: 32),
                    _buildMembersSection(colorScheme),
                    const SizedBox(height: 24),
                    _buildGroupSettingsSection(colorScheme),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildSaveBar(colorScheme),
    );
  }

  Widget _buildMembersSection(ColorScheme colorScheme) {
    final theme = Theme.of(context);
    final textTheme = AppTheme.uiTextTheme(theme.textTheme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Members',
                    style: textTheme.headlineMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manage group participants.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: _copyLink,
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Copy Link'),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: const StadiumBorder(),
                textStyle: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_members.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                'No members loaded',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: _members.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final member = _members[index];
              final isMe = member.uid == widget.auth.currentUser?.uid;
              final isMemberOwner = member.uid == widget.group.ownerUid;
              final role = isMemberOwner ? 'Group Admin' : 'Member';
              final isOwner =
                  widget.group.ownerUid == widget.auth.currentUser?.uid;

              return Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                  ),
                  borderRadius: BorderRadius.circular(50),
                ),
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: isMemberOwner
                          ? colorScheme.tertiaryContainer
                          : colorScheme.secondaryContainer,
                      backgroundImage: member.photoUrl != null
                          ? CachedNetworkImageProvider(member.photoUrl!)
                          : null,
                      child: member.photoUrl == null
                          ? Text(
                              member.name.isNotEmpty
                                  ? member.name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: isMemberOwner
                                    ? colorScheme.onTertiaryContainer
                                    : colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.name,
                            style: textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            role,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isOwner && !isMe)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        color: colorScheme.onSurfaceVariant,
                        tooltip: 'Remove member',
                        onPressed: () => _kickMember(member.uid, member.name),
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildGroupSettingsSection(ColorScheme colorScheme) {
    final theme = Theme.of(context);
    final textTheme = AppTheme.uiTextTheme(theme.textTheme);
    final isOwner = widget.auth.currentUser?.uid == widget.group.ownerUid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Group Settings',
          style: textTheme.headlineMedium?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Visibility and archival options.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 16),
        Container(
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
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 18,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Visible in community search results',
                      style: textTheme.bodyMedium?.copyWith(
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
                onChanged: (val) => setState(() => _isPublic = val),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (isOwner)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _archiveGroup,
              icon: Icon(Icons.inventory_2, color: colorScheme.tertiary),
              label: Text(
                'Archive Group',
                style: TextStyle(color: colorScheme.tertiary),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: colorScheme.tertiary.withValues(alpha: 0.3),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSaveBar(ColorScheme colorScheme) {
    final theme = Theme.of(context);
    final textTheme = AppTheme.uiTextTheme(theme.textTheme);
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              key: GroupPlanKeys.submitButton,
              onPressed: _isSaving ? null : _saveChanges,
              icon: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (_plan.days.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${_plan.totalChapters} chapters · ${_plan.days.length} days · ends ${formatPlanDateShort(_plan.finishesOn!)}',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

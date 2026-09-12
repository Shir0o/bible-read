import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_schedule.dart';
import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../services/plan_pace.dart';
import '../services/plan_pace_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/plan_day_list.dart';
import '../widgets/sub_header.dart';
import 'adjust_pace_page.dart';

/// Owner-only Reschedule: moves the Group schedule for every member.
///
/// This is deliberately separate from [AdjustPacePage]. Adjust pace writes
/// only the acting reader's private overlay; Reschedule rewrites the shared
/// schedule and its copy says who is affected before the owner commits.
class ReschedulePage extends StatefulWidget {
  final Group group;
  final GroupService groupService;
  final PlanPaceService paceService;
  final FirebaseAuth auth;
  final List<GroupSchedule> schedule;
  final Set<String> completedDateIds;
  final int daysBehind;
  final DateTime today;
  final VibrationService vibrationService;

  const ReschedulePage({
    super.key,
    required this.group,
    required this.groupService,
    required this.paceService,
    required this.auth,
    required this.schedule,
    required this.completedDateIds,
    required this.daysBehind,
    required this.today,
    this.vibrationService = const VibrationService(),
  });

  @override
  State<ReschedulePage> createState() => _ReschedulePageState();
}

class _ReschedulePageState extends State<ReschedulePage> {
  PaceOption? _selected;
  bool _saving = false;

  bool get _isOwner => widget.auth.currentUser?.uid == widget.group.ownerUid;

  List<GroupSchedule> _adjusted(
    PaceOption option, {
    Set<String>? completedDateIds,
  }) {
    final completed = completedDateIds ?? const <String>{};
    switch (option) {
      case PaceOption.stretch:
        return PlanPace.stretch(
          days: widget.schedule,
          completedDateIds: completed,
          daysBehind: widget.daysBehind,
        );
      case PaceOption.keepFinish:
        return PlanPace.redistribute(
          days: widget.schedule,
          completedDateIds: completed,
          resumeDate: PlanPace.resumeDate(
            widget.schedule,
            completed,
            today: widget.today,
          ),
          finishDate: PlanPace.finishOf(widget.schedule) ?? widget.today,
        );
      case PaceOption.beginAgain:
        return PlanPace.beginAgain(
          days: widget.schedule,
          startDate: PlanPace.resumeDate(
            widget.schedule,
            completed,
            today: widget.today,
          ),
        );
    }
  }

  String _previewLine(PaceOption option) {
    final finish = PlanPace.finishOf(_adjusted(option));
    final suffix = finish == null ? '' : ' - ends ${formatPlanDate(finish)}';
    switch (option) {
      case PaceOption.stretch:
        final days = widget.daysBehind;
        return days <= 0
            ? 'The dates stay as they are$suffix'
            : 'Everything shifts $days ${days == 1 ? 'day' : 'days'} later'
                '$suffix';
      case PaceOption.keepFinish:
        return 'The remaining readings spread across the days that are left'
            '$suffix';
      case PaceOption.beginAgain:
        return 'Restart from today at the original pace$suffix';
    }
  }

  Future<void> _reschedule() async {
    final option = _selected;
    final uid = widget.auth.currentUser?.uid;
    if (option == null || uid == null || _isOwner == false || _saving) {
      return;
    }
    unawaited(widget.vibrationService.lightImpact());
    setState(() => _saving = true);
    try {
      final adjusted = _adjusted(option);
      final revision = await widget.paceService.rescheduleGroup(
        uid: uid,
        groupId: widget.group.id,
        adjusted: adjusted,
      );
      unawaited(
        _repairProgress(
          uid: uid,
          adjusted: adjusted,
          revision: revision,
        ),
      );
      if (mounted == false) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rescheduled for "${widget.group.name}"')),
      );
      Navigator.pop(context, true);
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reschedule this group')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _repairProgress({
    required String uid,
    required List<GroupSchedule> adjusted,
    required int revision,
  }) async {
    try {
      final cloudOk = await widget.groupService.remapGroupProgressCallable(
        groupId: widget.group.id,
        newDays: adjusted,
      );
      if (cloudOk == false) {
        await widget.groupService.applyOwnRemap(
          groupId: widget.group.id,
          uid: uid,
          oldDays: widget.schedule,
          newDays: adjusted,
        );
      }
      await widget.groupService.markMemberRemapped(
        groupId: widget.group.id,
        uid: uid,
        revision: revision,
      );
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  Future<void> _adjustMyPaceInstead() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null || _saving) return;
    final choice = await Navigator.of(context).push<PaceOption>(
      MaterialPageRoute(
        builder: (_) => AdjustPacePage(
          days: widget.schedule,
          completedDateIds: widget.completedDateIds,
          daysBehind: widget.daysBehind,
          shared: true,
          today: widget.today,
          vibrationService: widget.vibrationService,
        ),
      ),
    );
    if (choice == null || mounted == false) return;
    setState(() => _saving = true);
    try {
      final adjusted = _adjusted(
        choice,
        completedDateIds: widget.completedDateIds,
      );
      await widget.paceService.applySharedPlanOverlay(
        uid: uid,
        groupId: widget.group.id,
        adjusted: adjusted,
      );
      if (mounted == false) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your pace adjusted - the Shared plan is unchanged'),
        ),
      );
      Navigator.pop(context, false);
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not adjust your pace')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);
    final memberCount = widget.group.memberCount;
    final memberLabel = memberCount == 1 ? 'member' : 'members';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            SubHeader(
                title: 'Reschedule', onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.hPadding,
                  4,
                  AppSpacing.hPadding,
                  20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Move the dates for ${widget.group.name}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontFamily: AppTheme.fontSerif,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _warningCard(context, memberCount, memberLabel),
                    const SizedBox(height: 18),
                    for (final option in PaceOption.values) ...[
                      _optionCard(context, option),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 12),
                    Divider(color: appColors.border),
                    const SizedBox(height: 14),
                    Text(
                      'Only you can do this',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'If it is only your own week that got away from you, '
                      'Adjust pace re-dates your copy and leaves the group\'s '
                      'schedule alone.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _saving ? null : _adjustMyPaceInstead,
                        child: const Text('Adjust my pace instead'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(top: BorderSide(color: appColors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.hPadding,
          12,
          AppSpacing.hPadding,
          20,
        ),
        child: FilledButton(
          onPressed: _selected == null || _saving || _isOwner == false
              ? null
              : _reschedule,
          child: _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Reschedule for everyone'),
        ),
      ),
    );
  }

  Widget _warningCard(BuildContext context, int count, String label) {
    final theme = Theme.of(context);
    final appColors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appColors.accentSoft,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: const Color(0xFFA0702F)),
              const SizedBox(width: 8),
              Text(
                'This changes everyone\'s dates',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: const Color(0xFFA0702F),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'All $count $label follow this schedule. Their readings move too, '
            'including ones they have already marked.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionCard(BuildContext context, PaceOption option) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);
    final selected = _selected == option;
    final (title, description) = switch (option) {
      PaceOption.stretch => (
          'Stretch the schedule',
          'Everything shifts later so the missed days stop being scheduled.',
        ),
      PaceOption.keepFinish => (
          'Keep the finish date',
          'The remaining readings spread across the days that are left. '
              'Slightly more each day.',
        ),
      PaceOption.beginAgain => (
          'Begin again',
          'Restart from today at the original pace. Nothing already marked '
              'is lost.',
        ),
    };
    return InkWell(
      onTap: _saving
          ? null
          : () {
              unawaited(widget.vibrationService.lightImpact());
              setState(() => _selected = option);
            },
      borderRadius: BorderRadius.circular(AppSpacing.rCard),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? appColors.primarySoft
              : colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.rCard),
          border: Border.all(
            color: selected ? appColors.primaryLine : appColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 22,
              color: selected ? colorScheme.primary : colorScheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _previewLine(option),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

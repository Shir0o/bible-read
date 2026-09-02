import 'dart:async';

import 'package:flutter/material.dart';

import '../models/group_plan_config.dart';
import '../services/schedule_generator.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_styles.dart';
import '../widgets/group_plan_keys.dart';
import '../widgets/plan_day_list.dart';
import '../widgets/sub_header.dart';

/// The whole plan, day by day, with each day's length adjustable.
///
/// Pops the edited draft, or null if the reader backed out. Writes nothing
/// itself — the screen that opened it owns persistence.
class AdjustDaysPage extends StatefulWidget {
  final GroupPlanDraft draft;
  final VibrationService vibrationService;

  const AdjustDaysPage({
    super.key,
    required this.draft,
    this.vibrationService = const VibrationService(),
  });

  @override
  State<AdjustDaysPage> createState() => _AdjustDaysPageState();
}

class _AdjustDaysPageState extends State<AdjustDaysPage> {
  late GroupPlanDraft _draft = widget.draft;
  late GeneratedPlan _plan = ScheduleGenerator.planFromDraft(_draft);

  void _setCount(int index, int count) {
    final overrides = {..._draft.dayOverrides, index: count};
    var next = _draft.copyWith(dayOverrides: overrides);
    var plan = ScheduleGenerator.planFromDraft(next);

    // Keep stored counts equal to what each day actually holds, so a value the
    // book boundary cut short does not reappear on the next tap.
    final reconciled = <int, int>{};
    next.dayOverrides.forEach((i, c) {
      if (i < plan.effectiveCounts.length) {
        reconciled[i] = plan.effectiveCounts[i];
      }
    });
    next = next.copyWith(dayOverrides: reconciled);
    plan = ScheduleGenerator.planFromDraft(next);

    setState(() {
      _draft = next;
      _plan = plan;
    });
  }

  void _evenItOut() {
    unawaited(widget.vibrationService.lightImpact());
    final next = _draft.copyWith(dayOverrides: const {});
    setState(() {
      _draft = next;
      _plan = ScheduleGenerator.planFromDraft(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);
    final hasEdits = _draft.dayOverrides.isNotEmpty;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            SubHeader(
              title: 'Adjust days',
              onBack: () => Navigator.pop(context),
              right: TextButton(
                key: GroupPlanKeys.evenItOutButton,
                onPressed: hasEdits ? _evenItOut : null,
                child: const Text('Even it out'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.hPadding,
                4,
                AppSpacing.hPadding,
                AppSpacing.gap12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Set what any one day holds. The days after it shift to '
                    'keep the reading in order.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.gap8),
                  Row(
                    children: [
                      _stat(context, '${_plan.totalChapters}', 'CHAPTERS'),
                      const SizedBox(width: AppSpacing.gap8),
                      _stat(context, '${_plan.days.length}', 'DAYS'),
                      const SizedBox(width: AppSpacing.gap8),
                      _stat(
                        context,
                        _plan.finishesOn == null
                            ? '—'
                            : formatPlanDateShort(_plan.finishesOn!),
                        'FINISHES',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.hPadding,
                  0,
                  AppSpacing.hPadding,
                  20,
                ),
                child: PlanDayList(
                  days: _plan.days,
                  overriddenDays: _draft.dayOverrides.keys.toSet(),
                  onSetCount: _setCount,
                  vibrationService: widget.vibrationService,
                ),
              ),
            ),
            Container(
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
                key: GroupPlanKeys.submitButton,
                onPressed: () => Navigator.pop(context, _draft),
                child: const Text('Save schedule'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);

    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.rField),
          border: Border.all(color: appColors.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: AppTheme.fontSerif,
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: AppTextStyles.eyebrow(context).copyWith(
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

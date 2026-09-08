import 'dart:async';

import 'package:flutter/material.dart';

import '../models/group_schedule.dart';
import '../services/plan_pace.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/plan_day_list.dart';
import '../widgets/sub_header.dart';

/// Which re-pacing the reader chose. The screen pops this; the opener owns
/// persistence — the screen writes nothing itself, matching AdjustDaysPage.
enum PaceOption { stretch, keepFinish, beginAgain }

/// One card per option: a short promise, the resulting finish date, and what
/// happens to what the reader has already done.
class _OptionCard extends StatelessWidget {
  final String title;
  final String description;
  final String preview;
  final bool selected;
  final VoidCallback onTap;

  const _OptionCard({
    required this.title,
    required this.description,
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: selected
            ? appColors.primarySoft
            : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(
          color: selected ? appColors.primaryLine : appColors.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 20,
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                preview,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Adjust pace" — the answer to "edit my plan" (#810, #790).
///
/// Three options, the same three Groups already answer with:
///  - Stretch: the finish moves out by the days behind; nothing is marked
///    missed.
///  - Keep the finish: the remaining readings spread across the days left.
///  - Begin again: day one becomes today; the Showing-up record stays.
///
/// Each card previews the finish date the choice produces before the reader
/// commits. On a Shared plan the screen says the change is theirs alone.
class AdjustPacePage extends StatefulWidget {
  /// The reader's current view of the schedule — for a Shared plan, the
  /// Group's schedule (the arithmetic runs on the same dated shape either
  /// way).
  final List<GroupSchedule> days;

  /// Date ids (`YYYY-MM-DD`) the reader has completed under this schedule.
  final Set<String> completedDateIds;

  /// The reader's own catch-up numbers, shown as-is on the cards.
  final int daysBehind;

  /// Whether this plan is Shared — a Group's schedule — rather than the
  /// reader's own.
  final bool shared;

  final DateTime today;
  final VibrationService vibrationService;

  const AdjustPacePage({
    super.key,
    required this.days,
    required this.completedDateIds,
    required this.daysBehind,
    required this.shared,
    required this.today,
    this.vibrationService = const VibrationService(),
  });

  @override
  State<AdjustPacePage> createState() => _AdjustPacePageState();
}

class _AdjustPacePageState extends State<AdjustPacePage> {
  PaceOption? _selected;

  DateTime? _previewFinish(PaceOption option) {
    final days = widget.days;
    switch (option) {
      case PaceOption.stretch:
        return PlanPace.finishOf(
          PlanPace.stretch(
            days: days,
            completedDateIds: widget.completedDateIds,
            daysBehind: widget.daysBehind,
          ),
        );
      case PaceOption.keepFinish:
        return PlanPace.finishOf(
          PlanPace.redistribute(
            days: days,
            completedDateIds: widget.completedDateIds,
            resumeDate: PlanPace.resumeDate(
              days,
              widget.completedDateIds,
              today: widget.today,
            ),
            finishDate: PlanPace.finishOf(days) ?? widget.today,
          ),
        );
      case PaceOption.beginAgain:
        return PlanPace.finishOf(
          PlanPace.beginAgain(
            days: days,
            startDate: PlanPace.resumeDate(
              days,
              widget.completedDateIds,
              today: widget.today,
            ),
          ),
        );
    }
  }

  String _previewLine(PaceOption option) {
    final finish = _previewFinish(option);
    final base = switch (option) {
      PaceOption.stretch =>
        'Finish moves ${widget.daysBehind == 1 ? 'a day' : '${widget.daysBehind} days'} later',
      PaceOption.keepFinish => 'Finish stays where it is',
      PaceOption.beginAgain => 'Day one becomes today',
    };
    return finish == null ? base : '$base · ends ${formatPlanDate(finish)}';
  }

  String _effectLine(PaceOption option) {
    final done = widget.completedDateIds.length;
    return switch (option) {
      PaceOption.stretch =>
        'Nothing is marked missed — the days you missed stop being scheduled.',
      PaceOption.keepFinish =>
        '$done completed ${done == 1 ? 'day stays' : 'days stay'} read; the rest spread evenly.',
      PaceOption.beginAgain =>
        'Your Showing-up record stays. The plan starts over from today.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);

    final options = [
      (
        PaceOption.stretch,
        'Stretch it out',
        'Take the pressure off: the finish moves out by the '
            '${widget.daysBehind == 1 ? 'day' : '${widget.daysBehind} days'} you are behind.',
      ),
      (
        PaceOption.keepFinish,
        'Keep the finish',
        'Catch up by reading a little more each day until the end date.',
      ),
      (
        PaceOption.beginAgain,
        'Begin again',
        'Start over from today with the same readings.',
      ),
    ];

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            SubHeader(
              title: 'Adjust pace',
              onBack: () => Navigator.pop(context),
            ),
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
                      'You are ${widget.daysBehind == 1 ? 'a day' : '${widget.daysBehind} days'} '
                      'behind. Pick how the plan should bend — none of them '
                      'erase what you have read.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.gap12),
                    for (final (option, title, description) in options) ...[
                      _OptionCard(
                        title: title,
                        description: description,
                        preview: _previewLine(option),
                        selected: _selected == option,
                        onTap: () {
                          unawaited(widget.vibrationService.lightImpact());
                          setState(() => _selected = option);
                        },
                      ),
                      if (_selected == option)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                          child: Text(
                            _effectLine(option),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                    if (widget.shared)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLowest,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.rField),
                          border: Border.all(color: appColors.border),
                        ),
                        child: Text(
                          'This is a shared plan — your change adjusts only '
                          'your own schedule. The plan your group follows, '
                          'and everyone else\'s progress, stay as they are.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
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
                onPressed: _selected == null
                    ? null
                    : () => Navigator.pop(context, _selected),
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
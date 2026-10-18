import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/group_schedule.dart';
import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';
import '../services/catch_up_engine.dart';
import '../services/error_logger.dart';
import '../services/plan_pace.dart';
import '../services/plan_pace_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/plan_day_list.dart';
import '../widgets/schedule_preview.dart';
import '../widgets/sub_header.dart';

/// Which re-pacing the reader chose. The screen pops this; the opener owns
/// persistence — the screen writes nothing itself, matching AdjustDaysPage.
enum PaceOption { stretch, keepFinish, chaptersPerDay, beginAgain }

/// Result payload returned by [AdjustPacePage].
class AdjustPaceResult {
  final PaceOption option;
  final int? chaptersPerDay;
  const AdjustPaceResult(this.option, {this.chaptersPerDay});
}

/// One card per option: a short promise, the resulting finish date, and what
/// happens to what the reader has already done.
class _OptionCard extends StatelessWidget {
  final String title;
  final String description;
  final String preview;
  final bool selected;
  final VoidCallback onTap;
  final Widget? extra;

  const _OptionCard({
    required this.title,
    required this.description,
    required this.preview,
    required this.selected,
    required this.onTap,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.gap12),
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
          padding: const EdgeInsets.all(AppSpacing.gap16),
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
              const SizedBox(height: AppSpacing.gap6),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.gap8),
              Text(
                preview,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (extra != null) ...[
                const SizedBox(height: AppSpacing.gap12),
                extra!,
              ],
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
  int _chaptersPerDay = 2;
  bool _showingReview = false;

  @override
  void initState() {
    super.initState();
    if (widget.days.isNotEmpty) {
      final firstWithChapters = widget.days.firstWhere(
        (d) => d.chapters.isNotEmpty,
        orElse: () => widget.days.first,
      );
      if (firstWithChapters.chapters.isNotEmpty) {
        _chaptersPerDay = firstWithChapters.chapters.length.clamp(1, 12);
      }
    }
  }

  List<GroupSchedule> _computeAdjusted(PaceOption option) {
    final days = widget.days;
    switch (option) {
      case PaceOption.stretch:
        return PlanPace.stretch(
          days: days,
          completedDateIds: widget.completedDateIds,
          daysBehind: widget.daysBehind,
        );
      case PaceOption.keepFinish:
        return PlanPace.redistribute(
          days: days,
          completedDateIds: widget.completedDateIds,
          resumeDate: PlanPace.resumeDate(
            days,
            widget.completedDateIds,
            today: widget.today,
          ),
          finishDate: PlanPace.finishOf(days) ?? widget.today,
        );
      case PaceOption.chaptersPerDay:
        return PlanPace.byChaptersPerDay(
          days: days,
          completedDateIds: widget.completedDateIds,
          resumeDate: PlanPace.resumeDate(
            days,
            widget.completedDateIds,
            today: widget.today,
          ),
          chaptersPerDay: _chaptersPerDay,
        );
      case PaceOption.beginAgain:
        return PlanPace.beginAgain(
          days: days,
          startDate: PlanPace.resumeDate(
            days,
            widget.completedDateIds,
            today: widget.today,
          ),
        );
    }
  }

  DateTime? _previewFinish(PaceOption option) {
    return PlanPace.finishOf(_computeAdjusted(option));
  }

  String _previewLine(PaceOption option) {
    final finish = _previewFinish(option);
    final base = switch (option) {
      PaceOption.stretch =>
        'Finish moves ${widget.daysBehind == 1 ? 'a day' : '${widget.daysBehind} days'} later',
      PaceOption.keepFinish => 'Finish stays where it is',
      PaceOption.chaptersPerDay =>
        '$_chaptersPerDay ${_chaptersPerDay == 1 ? 'chapter' : 'chapters'} a day',
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
      PaceOption.chaptersPerDay =>
        '$done completed ${done == 1 ? 'day stays' : 'days stay'} read; remaining chapters read at $_chaptersPerDay a day.',
      PaceOption.beginAgain =>
        'Your Showing-up record stays. The plan starts over from today.',
    };
  }

  String _formatPace(List<GroupSchedule> list) {
    if (list.isEmpty) return '—';
    final totalChapters =
        list.fold<int>(0, (total, d) => total + d.chapters.length);
    final avg = totalChapters / list.length;
    final formatted = avg == avg.roundToDouble()
        ? avg.toStringAsFixed(0)
        : avg.toStringAsFixed(1);
    return '$formatted ch/day';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_showingReview,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _showingReview) {
          setState(() => _showingReview = false);
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child:
              _showingReview ? _buildReview(context) : _buildOptions(context),
        ),
      ),
    );
  }

  Widget _buildOptions(BuildContext context) {
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
        PaceOption.chaptersPerDay,
        'Set chapters a day',
        'Read a set number of chapters each day until the plan is complete.',
      ),
      (
        PaceOption.beginAgain,
        'Begin again',
        'Start over from today with the same readings.',
      ),
    ];

    return Column(
      children: [
        SubHeader(
          title: 'Adjust pace',
          onBack: () => Navigator.pop(context),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.hPadding,
              AppSpacing.gap4,
              AppSpacing.hPadding,
              AppSpacing.gap20,
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
                    extra: option == PaceOption.chaptersPerDay &&
                            _selected == PaceOption.chaptersPerDay
                        ? _buildChaptersStepper(context)
                        : null,
                  ),
                  if (_selected == option)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.gap4, 0,
                          AppSpacing.gap4, AppSpacing.gap12),
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
                    padding: const EdgeInsets.all(AppSpacing.gap12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(AppSpacing.rField),
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
            AppSpacing.gap12,
            AppSpacing.hPadding,
            AppSpacing.gap20,
          ),
          child: FilledButton(
            onPressed: _selected == null
                ? null
                : () {
                    unawaited(widget.vibrationService.lightImpact());
                    setState(() => _showingReview = true);
                  },
            child: const Text('Preview changes'),
          ),
        ),
      ],
    );
  }

  Widget _buildChaptersStepper(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gap8,
        vertical: AppSpacing.gap4,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.rField),
        border: Border.all(color: appColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            key: const Key('chapters_per_day_decrement'),
            icon: const Icon(Icons.remove, size: 20),
            tooltip: 'Decrease chapters per day',
            onPressed: _chaptersPerDay > 1
                ? () {
                    unawaited(widget.vibrationService.lightImpact());
                    setState(() => _chaptersPerDay--);
                  }
                : null,
          ),
          Text(
            '$_chaptersPerDay ${_chaptersPerDay == 1 ? 'chapter' : 'chapters'} / day',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          IconButton(
            key: const Key('chapters_per_day_increment'),
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'Increase chapters per day',
            onPressed: _chaptersPerDay < 12
                ? () {
                    unawaited(widget.vibrationService.lightImpact());
                    setState(() => _chaptersPerDay++);
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildReview(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);

    final option = _selected!;
    final adjusted = _computeAdjusted(option);
    final completedForStatus = option == PaceOption.beginAgain
        ? const <String>{}
        : widget.completedDateIds;
    final status = CatchUpEngine.forGroupSchedule(
      adjusted,
      completedForStatus,
      today: widget.today,
    );

    return Column(
      children: [
        SubHeader(
          title: 'Review adjustment',
          onBack: () => setState(() => _showingReview = false),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.hPadding,
              AppSpacing.gap4,
              AppSpacing.hPadding,
              AppSpacing.gap20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Preserved readings badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.gap12,
                    vertical: AppSpacing.gap8,
                  ),
                  decoration: BoxDecoration(
                    color: appColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppSpacing.rField),
                    border: Border.all(color: appColors.primaryLine),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.gap8),
                      Expanded(
                        child: Text(
                          option == PaceOption.beginAgain
                              ? 'Showing-up record kept · Schedule resets'
                              : '${widget.completedDateIds.length} completed ${widget.completedDateIds.length == 1 ? 'reading' : 'readings'} kept',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.gap16),

                // Comparison card (Pace & Finish Date)
                _buildComparisonCard(context, adjusted),

                const SizedBox(height: AppSpacing.gap16),

                // Schedule Preview
                SchedulePreview(
                  status: status,
                  title: 'Schedule preview',
                  windowSize: 5,
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
            AppSpacing.gap12,
            AppSpacing.hPadding,
            AppSpacing.gap20,
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _showingReview = false),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: AppSpacing.gap12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    unawaited(widget.vibrationService.lightImpact());
                    Navigator.pop(
                      context,
                      AdjustPaceResult(
                        _selected!,
                        chaptersPerDay: _selected == PaceOption.chaptersPerDay
                            ? _chaptersPerDay
                            : null,
                      ),
                    );
                  },
                  child: const Text('Confirm & apply'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonCard(
    BuildContext context,
    List<GroupSchedule> adjusted,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);

    final prevFinish = PlanPace.finishOf(widget.days);
    final newFinish = PlanPace.finishOf(adjusted);

    final prevPace = _formatPace(widget.days);
    final newPace = _selected == PaceOption.chaptersPerDay
        ? '$_chaptersPerDay ch/day'
        : _formatPace(adjusted);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.gap16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(color: appColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Timeline & pace comparison',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.gap12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCol(
                  context,
                  label: 'Previous pace',
                  value: prevPace,
                ),
              ),
              const SizedBox(width: AppSpacing.gap12),
              Expanded(
                child: _buildMetricCol(
                  context,
                  label: 'New pace',
                  value: newPace,
                  highlight: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.gap12),
          Divider(height: 1, color: appColors.border),
          const SizedBox(height: AppSpacing.gap12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCol(
                  context,
                  label: 'Previous finish',
                  value: prevFinish != null ? formatPlanDate(prevFinish) : '—',
                ),
              ),
              const SizedBox(width: AppSpacing.gap12),
              Expanded(
                child: _buildMetricCol(
                  context,
                  label: 'New finish',
                  value: newFinish != null ? formatPlanDate(newFinish) : '—',
                  highlight: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCol(
    BuildContext context, {
    required String label,
    required String value,
    bool highlight = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.gap4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: highlight ? colorScheme.primary : colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Runs the Adjust pace flow on a personal plan (#810): the options run
/// against the plan's dated schedule, and the chosen one is persisted in
/// place. Shared by Path's plan card and Home's Plan ended card. Returns
/// whether a pace was applied, so the caller can refresh.
Future<bool> adjustPersonalPace(
  BuildContext context, {
  required FirebaseFirestore firestore,
  required String uid,
  required ReadingPlan plan,
  required UserPlanProgress progress,
  required DateTime today,
  required VibrationService vibrationService,
}) async {
  vibrationService.lightImpact();
  final days = PlanPace.datedPersonalSchedule(plan, progress.startDate);
  final completed = PlanPace.personalCompletedDateIds(plan, progress);
  final behind = PlanPace.daysBehind(days, completed, today: today);
  final choice = await Navigator.of(context).push<AdjustPaceResult>(
    MaterialPageRoute(
      builder: (_) => AdjustPacePage(
        days: days,
        completedDateIds: completed,
        daysBehind: behind,
        shared: false,
        today: today,
        vibrationService: vibrationService,
      ),
    ),
  );
  if (choice == null || !context.mounted) return false;
  try {
    final paceService = PlanPaceService(firestore: firestore);
    switch (choice.option) {
      case PaceOption.stretch:
        await paceService.applyPersonalSchedule(
          uid: uid,
          plan: plan,
          startDate: progress.startDate,
          adjusted: PlanPace.stretch(
            days: days,
            completedDateIds: completed,
            daysBehind: behind,
          ),
        );
      case PaceOption.keepFinish:
        await paceService.applyPersonalSchedule(
          uid: uid,
          plan: plan,
          startDate: progress.startDate,
          adjusted: PlanPace.redistribute(
            days: days,
            completedDateIds: completed,
            resumeDate: PlanPace.resumeDate(days, completed, today: today),
            finishDate: PlanPace.finishOf(days) ?? today,
          ),
        );
      case PaceOption.chaptersPerDay:
        await paceService.applyPersonalSchedule(
          uid: uid,
          plan: plan,
          startDate: progress.startDate,
          adjusted: PlanPace.byChaptersPerDay(
            days: days,
            completedDateIds: completed,
            resumeDate: PlanPace.resumeDate(days, completed, today: today),
            chaptersPerDay: choice.chaptersPerDay ?? 2,
          ),
        );
      case PaceOption.beginAgain:
        await paceService.beginPersonalPlanAgain(
          uid: uid,
          plan: plan,
          startDate: PlanPace.resumeDate(days, completed, today: today),
          progress: progress,
        );
    }
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Pace adjusted for "${plan.title}"')),
    );
    return true;
  } catch (e, st) {
    ErrorLogger.log(e, st);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to adjust pace. Please try again.'),
        ),
      );
    }
    return false;
  }
}

/// Runs the Adjust pace flow on a Shared plan (#810): the arithmetic runs on
/// the Group's [schedule], but the outcome is stored as the reader's own
/// overlay — the Group's schedule and the other members' progress are never
/// written. Shared by Path's plan card and Home's Plan ended card. Returns
/// whether a pace was applied, so the caller can refresh.
Future<bool> adjustSharedPace(
  BuildContext context, {
  required FirebaseFirestore firestore,
  required String uid,
  required String groupId,
  required List<GroupSchedule> schedule,
  required Set<String> completedDateIds,
  required int daysBehind,
  required DateTime today,
  required VibrationService vibrationService,
}) async {
  vibrationService.lightImpact();
  final choice = await Navigator.of(context).push<AdjustPaceResult>(
    MaterialPageRoute(
      builder: (_) => AdjustPacePage(
        days: schedule,
        completedDateIds: completedDateIds,
        daysBehind: daysBehind,
        shared: true,
        today: today,
        vibrationService: vibrationService,
      ),
    ),
  );
  if (choice == null || !context.mounted) return false;
  try {
    final paceService = PlanPaceService(firestore: firestore);
    switch (choice.option) {
      case PaceOption.stretch:
        await paceService.applySharedPlanOverlay(
          uid: uid,
          groupId: groupId,
          adjusted: PlanPace.stretch(
            days: schedule,
            completedDateIds: completedDateIds,
            daysBehind: daysBehind,
          ),
        );
      case PaceOption.keepFinish:
        await paceService.applySharedPlanOverlay(
          uid: uid,
          groupId: groupId,
          adjusted: PlanPace.redistribute(
            days: schedule,
            completedDateIds: completedDateIds,
            resumeDate: PlanPace.resumeDate(
              schedule,
              completedDateIds,
              today: today,
            ),
            finishDate: PlanPace.finishOf(schedule) ?? today,
          ),
        );
      case PaceOption.chaptersPerDay:
        await paceService.applySharedPlanOverlay(
          uid: uid,
          groupId: groupId,
          adjusted: PlanPace.byChaptersPerDay(
            days: schedule,
            completedDateIds: completedDateIds,
            resumeDate: PlanPace.resumeDate(
              schedule,
              completedDateIds,
              today: today,
            ),
            chaptersPerDay: choice.chaptersPerDay ?? 2,
          ),
        );
      case PaceOption.beginAgain:
        await paceService.applySharedPlanOverlay(
          uid: uid,
          groupId: groupId,
          adjusted: PlanPace.beginAgain(
            days: schedule,
            startDate: PlanPace.resumeDate(
              schedule,
              completedDateIds,
              today: today,
            ),
          ),
        );
    }
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your pace adjusted — the Shared plan is unchanged'),
      ),
    );
    return true;
  } catch (e, st) {
    ErrorLogger.log(e, st);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to adjust pace. Please try again.'),
        ),
      );
    }
    return false;
  }
}

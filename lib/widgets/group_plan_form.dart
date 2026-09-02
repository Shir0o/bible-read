import 'dart:async';

import 'package:flutter/material.dart';

import '../models/group_plan_config.dart';
import '../models/schedule_mode.dart';
import '../services/reference_parser.dart';
import '../services/schedule_generator.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import 'common_styles.dart';
import 'group_plan_keys.dart';
import 'plan_day_list.dart';
import 'start_chapter_sheet.dart';
import 'starts_at_card.dart';
import 'stepper_control.dart';

/// The reading-plan configurator shared by group create and group edit.
///
/// Owns no persistence: it hands the host both the draft and the schedule that
/// draft generates, so a screen's summary can never disagree with the preview
/// it sits under.
class GroupPlanForm extends StatefulWidget {
  final GroupPlanDraft initial;

  /// Fires on every edit with the configuration and the plan it produces.
  final void Function(GroupPlanDraft draft, GeneratedPlan plan) onChanged;

  /// Days to show in the preview. Null shows all of them.
  final int? previewDays;

  /// Opens the full day-by-day screen. Hidden when null.
  final Future<GroupPlanDraft?> Function(GroupPlanDraft draft)? onSeeAllDays;

  final VibrationService vibrationService;

  const GroupPlanForm({
    super.key,
    required this.initial,
    required this.onChanged,
    this.previewDays = 3,
    this.onSeeAllDays,
    this.vibrationService = const VibrationService(),
  });

  @override
  State<GroupPlanForm> createState() => _GroupPlanFormState();
}

class _GroupPlanFormState extends State<GroupPlanForm> {
  late GroupPlanDraft _draft;
  late GeneratedPlan _plan;

  static const _weekdayLetters = [
    ('M', 1),
    ('T', 2),
    ('W', 3),
    ('T', 4),
    ('F', 5),
    ('S', 6),
    ('S', 7),
  ];

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    _plan = ScheduleGenerator.planFromDraft(_draft);
    // Report the starting state so the host renders its summary immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged(_draft, _plan);
    });
  }

  /// Regenerates and republishes. Hand-set counts are reconciled against what
  /// each day actually holds, so a stored 5 that a book boundary cut to 1 does
  /// not make the next tap of `+` jump to 2.
  void _apply(GroupPlanDraft draft, {bool clearOverrides = false}) {
    var next = clearOverrides ? draft.copyWith(dayOverrides: const {}) : draft;
    var plan = ScheduleGenerator.planFromDraft(next);

    if (next.dayOverrides.isNotEmpty) {
      final reconciled = <int, int>{};
      next.dayOverrides.forEach((index, count) {
        // Drop overrides for days the plan no longer has.
        if (index >= plan.effectiveCounts.length) {
          return;
        }
        reconciled[index] = plan.effectiveCounts[index];
      });
      if (!_sameOverrides(reconciled, next.dayOverrides)) {
        next = next.copyWith(dayOverrides: reconciled);
        plan = ScheduleGenerator.planFromDraft(next);
      }
    }

    setState(() {
      _draft = next;
      _plan = plan;
    });
    widget.onChanged(next, plan);
  }

  /// How many of [book]'s chapters the plan actually schedules.
  ///
  /// A book wholly ahead of the start point contributes nothing, and the book
  /// the plan starts inside contributes only its tail — so a chip can say
  /// "skipped" instead of advertising chapters nobody will read.
  int _scheduledIn(String book) {
    var offset = 0;
    for (final b in _draft.books) {
      final total = ReferenceParser.chapterCount(b) ?? 0;
      if (b == book) {
        final skipped = _plan.skippedBeforeStart - offset;
        if (skipped <= 0) return total;
        if (skipped >= total) return 0;
        return total - skipped;
      }
      offset += total;
    }
    return 0;
  }

  static bool _sameOverrides(Map<int, int> a, Map<int, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  void _addBook(String book) {
    if (_draft.books.contains(book)) return;
    final books = [..._draft.books, book];
    // A first book settles where the plan starts.
    final startRef = _draft.startRef.isEmpty ? '$book 1' : _draft.startRef;
    _apply(
      _draft.copyWith(books: books, startRef: startRef),
      clearOverrides: true,
    );
  }

  void _removeBook(String book) {
    final books = _draft.books.where((b) => b != book).toList();
    final startBook = ReferenceParser.parseBook(_draft.startRef);
    // Dropping the book the plan started at moves the start to what is left.
    final startRef = startBook == book
        ? (books.isEmpty ? '' : '${books.first} 1')
        : _draft.startRef;
    _apply(
      _draft.copyWith(books: books, startRef: startRef),
      clearOverrides: true,
    );
  }

  void _toggleWeekday(int weekday) {
    final days = [..._draft.weekdays];
    if (days.contains(weekday)) {
      if (days.length == 1) return; // a plan needs at least one reading day
      days.remove(weekday);
    } else {
      days.add(weekday);
    }
    days.sort();
    _apply(_draft.copyWith(weekdays: days), clearOverrides: true);
  }

  Future<void> _changeStart() async {
    unawaited(widget.vibrationService.lightImpact());
    final picked = await showStartChapterSheet(
      context,
      books: _draft.books,
      currentRef: _draft.startRef,
      vibrationService: widget.vibrationService,
    );
    if (picked == null || !mounted) return;
    // Day indices mean nothing once the plan starts somewhere else.
    _apply(_draft.copyWith(startRef: picked), clearOverrides: true);
  }

  Future<void> _seeAllDays() async {
    final updated = await widget.onSeeAllDays!(_draft);
    if (updated == null || !mounted) return;
    _apply(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(context, 'What you\'ll read'),
        Text(
          'Books are read in the order you add them.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.gap12),
        _buildBooks(context),
        if (_draft.books.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.gap24),
          StartsAtCard(
            startRef: _draft.startRef,
            skippedBefore: _plan.skippedBeforeStart,
            onChange: _changeStart,
          ),
        ],
        const SizedBox(height: AppSpacing.gap24),
        _section(context, 'Pace'),
        _buildPace(context),
        const SizedBox(height: AppSpacing.gap24),
        _section(context, 'Reading days'),
        _buildWeekdays(context),
        if (_plan.days.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.gap24),
          _section(
            context,
            widget.previewDays == null ? 'Every day' : 'The first few days',
          ),
          Text(
            'Hold a day to a different length and the days after it shift to '
            'match.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.gap12),
          PlanDayList(
            days: _plan.days,
            overriddenDays: _draft.dayOverrides.keys.toSet(),
            maxRows: widget.previewDays,
            vibrationService: widget.vibrationService,
            onSetCount: (index, count) => _apply(
              _draft.copyWith(
                dayOverrides: {..._draft.dayOverrides, index: count},
              ),
            ),
            footer: _buildPreviewFooter(context),
          ),
          const SizedBox(height: AppSpacing.gap12),
          _buildBoundarySwitch(context),
        ],
      ],
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.gap8),
        child: Text(title, style: AppTextStyles.sectionTitle(context)),
      );

  Widget _buildBooks(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Autocomplete<String>(
          optionsBuilder: (value) {
            if (value.text.isEmpty) return const Iterable<String>.empty();
            return ReferenceParser.allBooks.where(
              (b) =>
                  b.toLowerCase().contains(value.text.toLowerCase()) &&
                  !_draft.books.contains(b),
            );
          },
          onSelected: _addBook,
          fieldViewBuilder: (context, controller, focusNode, onSubmit) {
            return TextField(
              key: GroupPlanKeys.bookSearchField,
              controller: controller,
              focusNode: focusNode,
              onEditingComplete: onSubmit,
              decoration: const InputDecoration(
                hintText: 'Add a book…',
                prefixIcon: Icon(Icons.search),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(AppSpacing.rField),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: 220, maxWidth: 320),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, i) {
                      final option = options.elementAt(i);
                      return InkWell(
                        onTap: () {
                          unawaited(widget.vibrationService.lightImpact());
                          onSelected(option);
                        },
                        child: Semantics(
                          button: true,
                          label: 'Add $option',
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(option),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        if (_draft.books.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.gap12),
          Wrap(
            spacing: AppSpacing.gap8,
            runSpacing: AppSpacing.gap8,
            children: [
              for (final book in _draft.books)
                Builder(
                  builder: (context) {
                    final scheduled = _scheduledIn(book);
                    final skipped = scheduled == 0;
                    return Container(
                      key: GroupPlanKeys.bookChip(book),
                      height: 44,
                      padding: const EdgeInsets.only(left: 14, right: 6),
                      decoration: BoxDecoration(
                        color: skipped
                            ? colorScheme.surfaceContainer
                            : appColors.primarySoft,
                        borderRadius: BorderRadius.circular(AppSpacing.rChip),
                        border: Border.all(
                          color: skipped
                              ? appColors.border
                              : appColors.primaryLine,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            book,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: skipped
                                  ? colorScheme.outline
                                  : appColors.primaryPress,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.gap8),
                          Text(
                            skipped ? 'skipped' : '$scheduled ch',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.outline,
                            ),
                          ),
                          IconButton(
                            key: GroupPlanKeys.removeBook(book),
                            tooltip: 'Remove $book',
                            onPressed: () {
                              unawaited(widget.vibrationService.lightImpact());
                              _removeBook(book);
                            },
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 44,
                            ),
                            icon: Icon(
                              Icons.close,
                              size: 15,
                              color: skipped
                                  ? colorScheme.outline
                                  : appColors.primaryPress,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildPace(BuildContext context) {
    final theme = Theme.of(context);
    final isPerDay = _draft.mode == ScheduleMode.chaptersPerDay;
    final finish = _plan.finishesOn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<ScheduleMode>(
          key: GroupPlanKeys.paceModeSegment,
          segments: const [
            ButtonSegment(
              value: ScheduleMode.chaptersPerDay,
              label: Text('Chapters a day'),
            ),
            ButtonSegment(
              value: ScheduleMode.endDate,
              label: Text('By end date'),
            ),
          ],
          selected: {_draft.mode},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            unawaited(widget.vibrationService.lightImpact());
            final mode = selection.first;
            _apply(
              _draft.copyWith(
                mode: mode,
                chaptersPerDay: mode == ScheduleMode.chaptersPerDay
                    ? (_draft.chaptersPerDay ?? 2)
                    : null,
                clearChaptersPerDay: mode == ScheduleMode.endDate,
              ),
              clearOverrides: true,
            );
          },
        ),
        const SizedBox(height: AppSpacing.gap12),
        _card(
          context,
          title: isPerDay ? 'Chapters a day' : 'Finish by',
          subtitle: _paceSubtitle(context),
          trailing: isPerDay
              ? StepperControl(
                  key: GroupPlanKeys.chaptersPerDayStepper,
                  value: _draft.chaptersPerDay ?? 2,
                  max: 12,
                  decrementLabel: 'Fewer chapters a day',
                  incrementLabel: 'More chapters a day',
                  vibrationService: widget.vibrationService,
                  onChanged: (v) => _apply(_draft.copyWith(chaptersPerDay: v)),
                )
              : OutlinedButton.icon(
                  key: GroupPlanKeys.endDateButton,
                  onPressed: _pickEndDate,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    _draft.endDate == null
                        ? 'Choose'
                        : formatPlanDateShort(_draft.endDate!),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    textStyle: theme.textTheme.titleSmall,
                  ),
                ),
        ),
        if (!isPerDay && _draft.endDate != null && finish != null)
          _overshootNote(context, finish),
      ],
    );
  }

  String _paceSubtitle(BuildContext context) {
    if (_plan.days.isEmpty) return 'Add a book to see the pace.';
    final finish = _plan.finishesOn!;
    if (_draft.mode == ScheduleMode.chaptersPerDay) {
      return '${_plan.totalChapters} chapters · ${_plan.days.length} '
          'reading days';
    }
    return 'About ${(_plan.totalChapters / _plan.days.length).round()} '
        'chapters a day · finishes ${formatPlanDateShort(finish)}';
  }

  /// Book boundaries can push a plan past the date that was asked for. Say so
  /// rather than quietly moving days the reader did not touch.
  Widget _overshootNote(BuildContext context, DateTime finish) {
    final end = _draft.endDate!;
    if (!finish.isAfter(DateTime(end.year, end.month, end.day))) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.gap8),
      child: Text(
        'Keeping books on their own days runs the plan to '
        '${formatPlanDateShort(finish)}.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Future<void> _pickEndDate() async {
    unawaited(widget.vibrationService.lightImpact());
    final picked = await showDatePicker(
      context: context,
      initialDate: _draft.endDate ?? _draft.startDate,
      firstDate: _draft.startDate,
      lastDate: _draft.startDate.add(const Duration(days: 365 * 5)),
    );
    if (picked == null || !mounted) return;
    _apply(_draft.copyWith(endDate: picked), clearOverrides: true);
  }

  Widget _buildWeekdays(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final preset in const [
              ('Daily', [1, 2, 3, 4, 5, 6, 7]),
              ('Weekdays', [1, 2, 3, 4, 5]),
            ])
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.gap8),
                child: ActionChip(
                  key: GroupPlanKeys.weekdayPreset(preset.$1),
                  label: Text(preset.$1),
                  onPressed: () {
                    unawaited(widget.vibrationService.lightImpact());
                    _apply(
                      _draft.copyWith(weekdays: preset.$2),
                      clearOverrides: true,
                    );
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.gap12),
        // Seven 44px targets plus gaps exactly fill a 390pt screen and overflow
        // a narrower one, so the circles flex rather than holding a fixed width.
        Row(
          spacing: 7,
          children: [
            for (final (letter, weekday) in _weekdayLetters)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: _draft.weekdays.contains(weekday),
                  child: InkWell(
                    key: GroupPlanKeys.weekday(weekday),
                    onTap: () {
                      unawaited(widget.vibrationService.lightImpact());
                      _toggleWeekday(weekday);
                    },
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        color: _draft.weekdays.contains(weekday)
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerLowest,
                        border: Border.all(
                          color: _draft.weekdays.contains(weekday)
                              ? colorScheme.primary
                              : appColors.border,
                        ),
                      ),
                      child: Text(
                        letter,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: _draft.weekdays.contains(weekday)
                              ? colorScheme.onPrimary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget? _buildPreviewFooter(BuildContext context) {
    final shown = widget.previewDays;
    if (shown == null) return null;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);
    final rest = _plan.days.length - shown;
    final finish = _plan.finishesOn;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: appColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              rest > 0 && finish != null
                  ? '$rest more days · finishes '
                      '${formatPlanDateShort(finish)}'
                  : 'That is the whole plan.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (widget.onSeeAllDays != null)
            TextButton(
              key: GroupPlanKeys.seeAllDaysButton,
              onPressed: _seeAllDays,
              child: const Text('See all'),
            ),
        ],
      ),
    );
  }

  Widget _buildBoundarySwitch(BuildContext context) {
    return _card(
      context,
      title: 'Start each book on its own day',
      subtitle: _draft.bookBoundary
          ? 'A day never ends one book and begins the next.'
          : 'A day may end one book and begin the next.',
      trailing: Switch(
        key: GroupPlanKeys.bookBoundarySwitch,
        value: _draft.bookBoundary,
        onChanged: (value) {
          unawaited(widget.vibrationService.lightImpact());
          _apply(_draft.copyWith(bookBoundary: value), clearOverrides: true);
        },
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(color: appColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.gap12),
          trailing,
        ],
      ),
    );
  }
}

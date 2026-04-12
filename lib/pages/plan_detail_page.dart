import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';
import '../services/reading_plan_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/skeletons/plan_detail_skeleton.dart';
import '../services/vibration_service.dart';

class PlanDetailPage extends StatefulWidget {
  final ReadingPlan plan;
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final UserPlanProgress? initialProgress;
  final VibrationService vibrationService;

  const PlanDetailPage({
    super.key,
    required this.plan,
    required this.firestore,
    required this.auth,
    this.initialProgress,
    this.vibrationService = const VibrationService(),
  });

  @override
  State<PlanDetailPage> createState() => _PlanDetailPageState();
}

class _PlanDetailPageState extends State<PlanDetailPage> {
  late final ReadingPlanService _planService;
  late Stream<UserPlanProgress?> _progressStream;
  Set<int>? _optimisticCompletedDays;

  @override
  void initState() {
    super.initState();
    _planService = ReadingPlanService(firestore: widget.firestore);
    final user = widget.auth.currentUser;
    if (user != null) {
      _progressStream = _planService.getPlanProgress(user.uid, widget.plan.id);
    } else {
      _progressStream = Stream.value(null);
    }
  }

  Future<void> _startPlan() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final currentYear = now.year;
    final jan1 = DateTime(currentYear, 1, 1);

    final DateTime? pickedDate = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'When would you like to start?',
                  style: AppTextStyles.subtitle(context),
                ),
                const SizedBox(height: 24),
                ListTile(
                  leading: const Icon(Icons.today),
                  title: const Text('Start Today'),
                  subtitle: Text(_formatDate(now)),
                  onTap: () => Navigator.pop(context, now),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                if (jan1.isBefore(now)) ...[
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Start on January 1st'),
                    subtitle: const Text('Catch up or join late'),
                    onTap: () => Navigator.pop(context, jan1),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ],
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.edit_calendar),
                  title: const Text('Pick a Date'),
                  subtitle: const Text('Choose a custom start date'),
                  onTap: () async {
                    final customDate = await showDatePicker(
                      context: context,
                      initialDate: now,
                      firstDate: DateTime(currentYear - 1),
                      lastDate: DateTime(currentYear + 2),
                    );
                    if (context.mounted && customDate != null) {
                      Navigator.pop(context, customDate);
                    }
                  },
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (pickedDate != null) {
      await _planService.startPlan(user.uid, widget.plan.id,
          startDate: pickedDate);
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  String _formatDayOfWeek(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface.withValues(alpha: 0.95),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.plan.title,
          style: theme.textTheme.titleLarge,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
            height: 1,
          ),
        ),
      ),
      body: StreamBuilder<UserPlanProgress?>(
        stream: _progressStream,
        initialData: widget.initialProgress,
        builder: (context, snapshot) {
          final isLoading =
              snapshot.connectionState == ConnectionState.waiting &&
                  snapshot.data == null;
          final streamProgress = snapshot.data;
          final isStarted = streamProgress != null;

          return SkeletonLoader(
            loading: isLoading,
            minTime: const Duration(milliseconds: 1000),
            skeleton: const PlanDetailSkeleton(),
            child: _PlanDetailContent(
              plan: widget.plan,
              progress: streamProgress,
              isStarted: isStarted,
              optimisticCompletedDays: _optimisticCompletedDays,
              onToggleDay: _toggleDay,
              onStartPlan: _startPlan,
              formatDate: _formatDate,
              formatDayOfWeek: _formatDayOfWeek,
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleDay(
      int dayNumber, bool wasCompleted, Set<int> completedDays) async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    unawaited(widget.vibrationService.lightImpact());

    final previousOptimistic = _optimisticCompletedDays != null
        ? Set<int>.from(_optimisticCompletedDays!)
        : (await _planService.getPlanProgress(user.uid, widget.plan.id).first)
                ?.completedDays
                .toSet() ??
            {};

    setState(() {
      final newCompletedDays = Set<int>.from(completedDays);
      if (wasCompleted) {
        newCompletedDays.remove(dayNumber);
      } else {
        newCompletedDays.add(dayNumber);
      }
      _optimisticCompletedDays = newCompletedDays;
    });

    try {
      if (wasCompleted) {
        await _planService.unmarkDayComplete(
            user.uid, widget.plan.id, dayNumber);
      } else {
        await _planService.markDayComplete(user.uid, widget.plan.id, dayNumber);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _optimisticCompletedDays = previousOptimistic;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update progress. Please try again.'),
          ),
        );
      }
    }
  }
}

class _PlanDetailContent extends StatefulWidget {
  final ReadingPlan plan;
  final UserPlanProgress? progress;
  final bool isStarted;
  final Set<int>? optimisticCompletedDays;
  final Function(int, bool, Set<int>) onToggleDay;
  final VoidCallback onStartPlan;
  final String Function(DateTime) formatDate;
  final String Function(DateTime) formatDayOfWeek;

  const _PlanDetailContent({
    required this.plan,
    required this.progress,
    required this.isStarted,
    this.optimisticCompletedDays,
    required this.onToggleDay,
    required this.onStartPlan,
    required this.formatDate,
    required this.formatDayOfWeek,
  });

  @override
  State<_PlanDetailContent> createState() => _PlanDetailContentState();
}

class _PlanDetailContentState extends State<_PlanDetailContent> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  bool _hasScrolledToUnchecked = false;

  @override
  void initState() {
    super.initState();
    if (widget.isStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_scrollToFirstUnchecked());
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _scrollToFirstUnchecked() async {
    if (_hasScrolledToUnchecked) return;

    final completedDays = widget.optimisticCompletedDays ??
        widget.progress?.completedDays.toSet() ??
        {};

    int? targetDay;
    for (final day in widget.plan.schedule) {
      if (!completedDays.contains(day.day)) {
        targetDay = day.day;
        break;
      }
    }

    if (targetDay != null && _itemKeys.containsKey(targetDay)) {
      final key = _itemKeys[targetDay];
      final context = key?.currentContext;
      if (context != null) {
        _hasScrolledToUnchecked = true;

        // 1. Initial jump to a position slightly above the target
        // We use alignment: 0.3 to put it a bit lower than the top initially
        Scrollable.ensureVisible(
          context,
          alignment: 0.3,
        );

        // 2. Short delay to let the jump settle
        await Future.delayed(const Duration(milliseconds: 100));

        // 3. Smooth scroll to the final position (alignment: 0.1)
        final currentContext = key?.currentContext;
        if (currentContext != null && currentContext.mounted) {
          await Scrollable.ensureVisible(
            currentContext,
            alignment: 0.1,
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeInOut,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!widget.isStarted) {
      return _buildNotStartedState(context, colorScheme);
    }

    final completedDays = widget.optimisticCompletedDays ??
        widget.progress?.completedDays.toSet() ??
        {};

    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final startDate = widget.progress!.startDate;

    final past = <ReadingPlanDay>[];
    final today = <ReadingPlanDay>[];
    final upcoming = <ReadingPlanDay>[];

    for (final day in widget.plan.schedule) {
      final date = startDate.add(Duration(days: day.day - 1));
      final sDate = DateTime(date.year, date.month, date.day);

      if (sDate.isBefore(todayDate)) {
        past.add(day);
      } else if (sDate.isAtSameMomentAs(todayDate)) {
        today.add(day);
      } else {
        upcoming.add(day);
      }
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 24, left: 8, right: 8),
            child: Text(
              widget.plan.description,
              style: AppTextStyles.body(context).copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (past.isNotEmpty) ...[
            _buildSectionHeader(context, 'Past Readings'),
            ...past.map((day) => _buildScheduleItem(
                  context,
                  day,
                  startDate,
                  completedDays,
                  isPast: true,
                )),
            const SizedBox(height: 16),
          ],
          if (today.isNotEmpty) ...[
            _buildSectionHeader(context, 'Today', isHighlight: true),
            ...today.map((day) => _buildTodayItem(
                  context,
                  day,
                  startDate,
                  completedDays,
                )),
            const SizedBox(height: 16),
          ],
          if (upcoming.isNotEmpty) ...[
            _buildSectionHeader(context, 'Upcoming'),
            ...upcoming.map((day) => _buildScheduleItem(
                  context,
                  day,
                  startDate,
                  completedDays,
                )),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildNotStartedState(BuildContext context, ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.plan.description,
                  style: AppTextStyles.body(context).copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: widget.onStartPlan,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start This Plan'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          _buildSectionHeader(context, 'Plan Preview'),
          ...widget.plan.schedule.map((day) => _buildScheduleItem(
                context,
                day,
                DateTime.now(),
                {},
                isStarted: false,
              )),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title,
      {bool isHighlight = false}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8, top: 8),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color:
              isHighlight ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildScheduleItem(
    BuildContext context,
    ReadingPlanDay day,
    DateTime startDate,
    Set<int> completedDays, {
    bool isPast = false,
    bool isStarted = true,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCompleted = completedDays.contains(day.day);
    final date = startDate.add(Duration(days: day.day - 1));
    final opacity = (isPast || isCompleted) ? 0.7 : 1.0;

    final key = _itemKeys.putIfAbsent(day.day, () => GlobalKey());

    return Opacity(
      key: key,
      opacity: opacity,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isCompleted
              ? colorScheme.surfaceContainerHigh
              : colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: !isStarted
              ? null
              : () => widget.onToggleDay(day.day, isCompleted, completedDays),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.formatDate(date),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        widget.formatDayOfWeek(date),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Day ${day.day}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        day.readings.join(', '),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurface.withValues(alpha: 0.8),
                          decoration:
                              isCompleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCompleted)
                  Icon(
                    Icons.check_circle,
                    color: colorScheme.primary,
                    size: 24,
                  )
                else
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.outline.withValues(alpha: 0.4),
                          width: 1,
                        )),
                  )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTodayItem(
    BuildContext context,
    ReadingPlanDay day,
    DateTime startDate,
    Set<int> completedDays,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCompleted = completedDays.contains(day.day);
    final date = startDate.add(Duration(days: day.day - 1));

    final key = _itemKeys.putIfAbsent(day.day, () => GlobalKey());

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isCompleted
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => widget.onToggleDay(day.day, isCompleted, completedDays),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.formatDate(date),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                      ),
                    ),
                    Text(
                      widget.formatDayOfWeek(date),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Day ${day.day}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      day.readings.join(', '),
                      style: theme.textTheme.titleMedium?.copyWith(
                        decoration:
                            isCompleted ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCompleted)
                Icon(
                  Icons.check_circle,
                  color: colorScheme.primary,
                  size: 24,
                )
              else
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorScheme.primary,
                        width: 2,
                      )),
                )
            ],
          ),
        ),
      ),
    );
  }
}

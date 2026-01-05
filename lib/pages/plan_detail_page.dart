import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';
import '../services/reading_plan_service.dart';
import '../widgets/common_styles.dart';

class PlanDetailPage extends StatefulWidget {
  final ReadingPlan plan;
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  const PlanDetailPage({
    super.key,
    required this.plan,
    required this.firestore,
    required this.auth,
  });

  @override
  State<PlanDetailPage> createState() => _PlanDetailPageState();
}

class _PlanDetailPageState extends State<PlanDetailPage> {
  late final ReadingPlanService _planService;
  late Stream<UserPlanProgress?> _progressStream;

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
    await _planService.startPlan(user.uid, widget.plan.id);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.plan.title),
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
       ),
      backgroundColor: colorScheme.surface,
      body: StreamBuilder<UserPlanProgress?>(
        stream: _progressStream,
        builder: (context, snapshot) {
          final progress = snapshot.data;
          final isStarted = progress != null;

          return Column(
            children: [
              // Header Info
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.plan.description,
                      style: AppTextStyles.body.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!isStarted)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _startPlan,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start This Plan'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle,
                                color: colorScheme.onSecondaryContainer),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Plan in Progress',
                                    style: AppTextStyles.subtitle.copyWith(
                                      color: colorScheme.onSecondaryContainer,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${progress.completedDays.length} / ${widget.plan.durationDays} days completed',
                                    style: AppTextStyles.caption.copyWith(
                                      color: colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Schedule List
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: widget.plan.schedule.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final day = widget.plan.schedule[index];
                    final isCompleted =
                        progress?.completedDays.contains(day.day) ?? false;
                    
                    return Opacity(
                        opacity: (!isStarted || isCompleted) ? 0.7 : 1.0,
                        child: Card(
                          elevation: 0,
                          color: isCompleted
                              ? colorScheme.surfaceContainerHigh
                              : colorScheme.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: isCompleted
                                  ? Colors.transparent
                                  : colorScheme.outlineVariant,
                            ),
                          ),
                          child: InkWell(
                            onTap: !isStarted
                                ? null
                                : () {
                                    final user = widget.auth.currentUser;
                                    if (user == null) return;

                                    if (isCompleted) {
                                      _planService.unmarkDayComplete(
                                          user.uid, widget.plan.id, day.day);
                                    } else {
                                      _planService.markDayComplete(
                                          user.uid, widget.plan.id, day.day);
                                    }
                                  },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: isCompleted
                                        ? colorScheme.primary
                                        : colorScheme.surfaceContainerHighest,
                                    child: isCompleted
                                        ? Icon(Icons.check,
                                            size: 16,
                                            color: colorScheme.onPrimary)
                                        : Text(
                                            '${day.day}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: colorScheme
                                                    .onSurfaceVariant),
                                          ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Day ${day.day}',
                                          style: AppTextStyles.caption.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          day.readings.join(', '),
                                          style: AppTextStyles.body.copyWith(
                                            fontSize: 16,
                                            decoration: isCompleted
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isStarted && !isCompleted)
                                     Icon(Icons.radio_button_unchecked, color: colorScheme.outline),
                                  if (isStarted && isCompleted)
                                     Icon(Icons.check_circle, color: colorScheme.primary),
                                ],
                              ),
                            ),
                          ),
                        ));
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

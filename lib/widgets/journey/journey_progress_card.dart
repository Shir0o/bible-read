import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/reading_plan.dart';
import '../../models/reading_plan_progress.dart';
import '../../services/reading_plan_service.dart';
import '../../pages/plan_detail_page.dart';
import '../../pages/reading_plans_page.dart';
import '../../pages/create_plan_page.dart';
import '../skeleton.dart';
import '../skeleton_loader.dart';
import '../../theme/app_theme.dart';

import '../../services/vibration_service.dart';

class JourneyProgressCard extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final ReadingPlanService readingPlanService;
  final VibrationService vibrationService;
  final List<ReadingPlan>? initialPlans;
  final List<UserPlanProgress>? initialProgress;
  final bool showTitle;
  final bool isLoading;

  JourneyProgressCard({
    super.key,
    required this.firestore,
    required this.auth,
    ReadingPlanService? readingPlanService,
    this.vibrationService = const VibrationService(),
    this.initialPlans,
    this.initialProgress,
    this.showTitle = true,
    this.isLoading = false,
  }) : readingPlanService =
            readingPlanService ?? ReadingPlanService(firestore: firestore);

  @override
  State<JourneyProgressCard> createState() => _JourneyProgressCardState();
}

class _ActivePlanData {
  final ReadingPlan? plan;
  final UserPlanProgress? progress;
  _ActivePlanData({this.plan, this.progress});
}

class _JourneyProgressCardState extends State<JourneyProgressCard> {
  late Future<List<ReadingPlan>> _allPlansFuture;
  late Stream<List<UserPlanProgress>> _activePlansStream;

  @override
  void initState() {
    super.initState();
    _allPlansFuture = widget.initialPlans != null
        ? Future.value(widget.initialPlans)
        : widget.readingPlanService
            .getAvailablePlans(userId: widget.auth.currentUser?.uid);
    final user = widget.auth.currentUser;
    if (user != null) {
      _activePlansStream = widget.initialProgress != null
          ? Stream.value(widget.initialProgress!)
          : widget.readingPlanService.getActivePlans(user.uid);
    } else {
      _activePlansStream = Stream.value([]);
    }
  }

  _ActivePlanData _computeActivePlan(
      List<ReadingPlan> plans, List<UserPlanProgress> userProgressList) {
    ReadingPlan? activePlan;
    UserPlanProgress? activeProgress;

    ReadingPlan? fallbackPlan;
    UserPlanProgress? fallbackProgress;

    for (final prog in userProgressList) {
      try {
        final p = plans.firstWhere((pl) => pl.id == prog.planId);
        if (prog.completedDays.length < p.durationDays) {
          activePlan = p;
          activeProgress = prog;
          break;
        } else if (fallbackPlan == null) {
          fallbackPlan = p;
          fallbackProgress = prog;
        }
      } catch (_) {
        // Plan might have been deleted or not loaded
      }
    }

    if (activePlan == null) {
      activePlan = fallbackPlan;
      activeProgress = fallbackProgress;
    }

    return _ActivePlanData(plan: activePlan, progress: activeProgress);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          if (widget.showTitle) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'My Personal Journey',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                ),
                TextButton(
                  onPressed: () async {
                    final edited = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => ReadingPlansPage(
                          firestore: widget.firestore,
                          auth: widget.auth,
                        ),
                      ),
                    );
                    if (edited == true && mounted) {
                      setState(() {
                        _allPlansFuture = widget.readingPlanService
                            .getAvailablePlans(
                                userId: widget.auth.currentUser?.uid);
                      });
                    }
                  },
                  child: Text(
                    'Details',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          SkeletonLoader(
            loading: widget.isLoading,
            minTime: const Duration(milliseconds: 1000),
            skeleton: _buildLoadingSkeleton(context),
            child: FutureBuilder<List<ReadingPlan>>(
              future: _allPlansFuture,
              builder: (context, plansSnapshot) {
                return StreamBuilder<List<UserPlanProgress>>(
                  stream: _activePlansStream,
                  builder: (context, progressSnapshot) {
                    // 1. Loading (Secondary loading for manual triggers)
                    if (plansSnapshot.connectionState ==
                            ConnectionState.waiting ||
                        progressSnapshot.connectionState ==
                            ConnectionState.waiting) {
                      return _buildLoadingSkeleton(context);
                    }

                    // 2. Data Check
                    final plans = plansSnapshot.data ?? [];
                    final userProgressList = progressSnapshot.data ?? [];

                    // 3. Compute Active Plan (Extracted logic)
                    final activeData =
                        _computeActivePlan(plans, userProgressList);
                    final activePlan = activeData.plan;
                    final activeProgress = activeData.progress;

                    // 4. No Active Plan (and no completed plan to show)
                    if (activePlan == null || activeProgress == null) {
                      return _buildNoActivePlanCard(context, colorScheme);
                    }

                    // 5. Active Plan Card
                    return _buildActivePlanCard(
                      context,
                      colorScheme,
                      activePlan,
                      activeProgress,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Skeleton(width: 80, height: 100, radius: 16),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Skeleton(width: double.infinity, height: 20),
                    const SizedBox(height: 8),
                    const Skeleton(width: 100, height: 12),
                    const SizedBox(height: 16),
                    const Skeleton(width: double.infinity, height: 8),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Skeleton(width: double.infinity, height: 48, radius: 16),
        ],
      ),
    );
  }

  Widget _buildNoActivePlanCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.auto_stories, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Start a Reading Plan',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose a plan to track your daily reading progress.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () async {
                final edited = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => CreatePlanPage(
                      firestore: widget.firestore,
                      auth: widget.auth,
                    ),
                  ),
                );
                if (edited == true && mounted) {
                  setState(() {
                    _allPlansFuture = widget.readingPlanService
                        .getAvailablePlans(
                            userId: widget.auth.currentUser?.uid);
                  });
                }
              },
              child: const Text('Create Plan'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivePlanCard(
    BuildContext context,
    ColorScheme colorScheme,
    ReadingPlan plan,
    UserPlanProgress progress,
  ) {
    final completedCount = progress.completedDays.length;
    final totalCount = plan.durationDays;
    final percent = totalCount > 0 ? completedCount / totalCount : 0.0;
    final percentString = '${(percent * 100).toInt()}%';

    // Calculate current day (next day to read)
    // Assuming simple sequential logic for "Day X" display
    final currentDay = completedCount + 1;
    final isCompleted = completedCount >= totalCount;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon Box
                      Container(
                        width: 80,
                        height: 100, // Slightly taller rectangle
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.1),
                          ),
                          boxShadow: AppSpacing.cardShadow(context),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.auto_stories,
                            size: 36,
                            color: colorScheme.primary.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Text Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    height: 1.2,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isCompleted ? 'Done' : 'Day $currentDay',
                                    style: TextStyle(
                                      color: colorScheme.onPrimaryContainer,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'of $totalCount • Personal Plan',
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Progress Bar Section
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '$percentString Completed',
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: percent,
                                minHeight: 8,
                                backgroundColor:
                                    colorScheme.surfaceContainerHighest,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.tonal(
                      onPressed: () {
                        unawaited(widget.vibrationService.lightImpact());
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlanDetailPage(
                              plan: plan,
                              firestore: widget.firestore,
                              auth: widget.auth,
                              initialProgress: progress,
                              vibrationService: widget.vibrationService,
                            ),
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.secondaryContainer,
                        foregroundColor: colorScheme.onSecondaryContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.play_arrow_rounded, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            isCompleted ? 'Review Plan' : 'Continue Reading',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
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

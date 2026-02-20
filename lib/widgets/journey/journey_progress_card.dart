import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/reading_plan.dart';
import '../../models/reading_plan_progress.dart';
import '../../pages/plan_detail_page.dart';
import '../../services/reading_plan_service.dart';
import '../../theme/app_theme.dart';
import '../views/reading_plans_view.dart';

class JourneyProgressCard extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  const JourneyProgressCard({
    super.key,
    required this.firestore,
    required this.auth,
  });

  @override
  State<JourneyProgressCard> createState() => _JourneyProgressCardState();
}

class _JourneyProgressCardState extends State<JourneyProgressCard> {
  late final ReadingPlanService _planService;
  late Future<List<ReadingPlan>> _allPlansFuture;
  late Stream<List<UserPlanProgress>> _activePlansStream;

  @override
  void initState() {
    super.initState();
    _planService = ReadingPlanService(firestore: widget.firestore);
    _allPlansFuture = _planService.getAvailablePlans();

    final user = widget.auth.currentUser;
    if (user != null) {
      _activePlansStream = _planService.getActivePlans(user.uid);
    } else {
      _activePlansStream = Stream.value([]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.hPadding),
      child: Column(
        children: [
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
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('Reading Plans')),
                        body: ReadingPlansView(
                          firestore: widget.firestore,
                          auth: widget.auth,
                        ),
                      ),
                    ),
                  );
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
          StreamBuilder<List<UserPlanProgress>>(
            stream: _activePlansStream,
            builder: (context, activeSnapshot) {
              if (activeSnapshot.hasError) {
                return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text("Error loading plan")));
              }

              final activeProgressList = activeSnapshot.data ?? [];

              return FutureBuilder<List<ReadingPlan>>(
                future: _allPlansFuture,
                builder: (context, plansSnapshot) {
                  if (plansSnapshot.connectionState == ConnectionState.waiting && activeProgressList.isEmpty) {
                     // Show loading skeleton if no data yet
                     return const Card(
                       child: SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                     );
                  }

                  final allPlans = plansSnapshot.data ?? [];

                  // Find the first active plan
                  UserPlanProgress? activeProgress;
                  ReadingPlan? activePlan;

                  if (activeProgressList.isNotEmpty) {
                    activeProgress = activeProgressList.first;
                    try {
                      activePlan = allPlans.firstWhere((p) => p.id == activeProgress!.planId);
                    } catch (e) {
                      // Plan not found in available plans (maybe deleted or specialized)
                    }
                  }

                  if (activePlan == null || activeProgress == null) {
                    return _buildNoActivePlanCard(context, colorScheme);
                  }

                  return _buildActivePlanCard(context, colorScheme, activePlan, activeProgress);
                },
              );
            },
          ),
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
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.auto_stories, size: 48),
            const SizedBox(height: 16),
            const Text(
              "Start a Reading Plan",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              "Choose a plan to track your daily reading progress.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () {
                 // Open plans tab or navigate
                 // Since we removed tabs, we might need a way to browse plans.
                 // For now, let's just leave it as is or show a dialog.
              },
              child: const Text("Browse Plans"),
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
      child: Stack(
        children: [
          // Background decorative elements (simplified)
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primary.withValues(alpha: 0.05),
              ),
            ),
          ),

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
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
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
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
                              backgroundColor: colorScheme.surfaceVariant,
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
                       Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlanDetailPage(
                              plan: plan,
                              firestore: widget.firestore,
                              auth: widget.auth,
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
    );
  }
}

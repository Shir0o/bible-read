import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/reading_plan.dart';
import '../../models/reading_plan_progress.dart';
import '../../pages/plan_detail_page.dart';
import '../../services/reading_plan_service.dart';
import '../common_styles.dart';

class ReadingPlansView extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  const ReadingPlansView({
    super.key,
    required this.firestore,
    required this.auth,
  });

  @override
  State<ReadingPlansView> createState() => _ReadingPlansViewState();
}

class _ReadingPlansViewState extends State<ReadingPlansView>
    with AutomaticKeepAliveClientMixin {
  late final ReadingPlanService _planService;
  late Future<List<ReadingPlan>> _allPlansFuture;
  late Stream<List<UserPlanProgress>> _activePlansStream;

  @override
  bool get wantKeepAlive => true;

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
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent, // Let parent background show
      body: StreamBuilder<List<UserPlanProgress>>(
        stream: _activePlansStream,
        builder: (context, activeSnapshot) {
          final activeProgress = activeSnapshot.data ?? [];

          return FutureBuilder<List<ReadingPlan>>(
            future: _allPlansFuture,
            builder: (context, plansSnapshot) {
              if (plansSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allPlans = plansSnapshot.data ?? [];
              
              // Filter plans: 
              // If a plan is active, we can show it in a "Current Plan" section.
              // All other plans go to "Available Plans".
              
              // For "Bible in a Year", typically users only have one active at a time, 
              // but we support multiple.
              
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (activeProgress.isNotEmpty) ...[
                    Text(
                      'Your Plans',
                      style: AppTextStyles.subtitle.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...activeProgress.map((progress) {
                      final plan = allPlans.firstWhere(
                        (p) => p.id == progress.planId, 
                        orElse: () => ReadingPlan(
                          id: 'unknown', 
                          title: 'Unknown Plan', 
                          description: '', 
                          durationDays: 0, 
                          tags: [], 
                          schedule: []
                        ),
                      );
                      
                      if (plan.id == 'unknown') return const SizedBox.shrink();

                      // Calculate next readings
                      final nextDay = _planService.getNextDueDay(plan, progress);
                      // Progress percentage
                      final percent = plan.durationDays > 0 
                          ? progress.completedDays.length / plan.durationDays 
                          : 0.0;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        color: colorScheme.secondaryContainer,
                        child: InkWell(
                          onTap: () {
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
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.auto_stories, color: colorScheme.onSecondaryContainer),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        plan.title,
                                        style: AppTextStyles.title.copyWith(
                                          fontSize: 18,
                                          color: colorScheme.onSecondaryContainer,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${(percent * 100).toInt()}%',
                                      style: AppTextStyles.body.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSecondaryContainer,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                LinearProgressIndicator(
                                  value: percent,
                                  backgroundColor: colorScheme.surface.withOpacity(0.3),
                                  color: colorScheme.onSecondaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                const SizedBox(height: 12),
                                if (nextDay != null) ...[
                                  Text(
                                    'Up next: Day ${nextDay.day}',
                                    style: AppTextStyles.caption.copyWith(
                                      color: colorScheme.onSecondaryContainer.withOpacity(0.8),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    nextDay.readings.join(', '),
                                    style: AppTextStyles.body.copyWith(
                                      color: colorScheme.onSecondaryContainer,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ] else 
                                  Text(
                                    'Plan Completed!',
                                    style: AppTextStyles.body.copyWith(
                                      color: colorScheme.onSecondaryContainer,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 24),
                  ],

                  Text(
                    'Available Plans',
                    style: AppTextStyles.subtitle.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...allPlans.where((p) => !activeProgress.any((ap) => ap.planId == p.id)).map((plan) {
                     return Card(
                      elevation: 0,
                      color: colorScheme.surfaceContainerHigh,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: colorScheme.outlineVariant.withOpacity(0.5),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
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
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.calendar_month,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      plan.title,
                                      style: AppTextStyles.title.copyWith(
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      '${plan.durationDays} Days',
                                      style: AppTextStyles.caption.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  
                  if (allPlans.where((p) => !activeProgress.any((ap) => ap.planId == p.id)).isEmpty && activeProgress.isEmpty)
                     const Padding(
                       padding: EdgeInsets.all(16.0),
                       child: Center(child: Text("No plans available right now.")),
                     ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

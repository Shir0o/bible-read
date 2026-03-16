import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';
import '../services/reading_plan_service.dart';

import 'plan_detail_page.dart';
import 'create_plan_page.dart';

class ReadingPlansPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  const ReadingPlansPage({
    super.key,
    required this.firestore,
    required this.auth,
  });

  @override
  State<ReadingPlansPage> createState() => _ReadingPlansPageState();
}

class _ReadingPlansPageState extends State<ReadingPlansPage> {
  late final ReadingPlanService _planService;
  late Future<List<ReadingPlan>> _plansFuture;

  @override
  void initState() {
    super.initState();
    _planService = ReadingPlanService(firestore: widget.firestore);
    final user = widget.auth.currentUser;
    _plansFuture = _planService.getAvailablePlans(userId: user?.uid);
  }

  void _leavePlan(ReadingPlan plan) {
    // Implement leave plan functionality if needed
    // Currently no 'leavePlan' in ReadingPlanService
    // Should remove progress doc from firestore
    final user = widget.auth.currentUser;
    if (user != null) {
      widget.firestore
          .collection('users')
          .doc(user.uid)
          .collection('plan_progress')
          .doc(plan.id)
          .delete()
          .then((_) {
        // Force refresh
        setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final user = widget.auth.currentUser;

    if (user == null) return const Scaffold(body: Center(child: Text('Not logged in')));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Reading Plans', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      backgroundColor: colorScheme.surface,
      body: FutureBuilder<List<ReadingPlan>>(
        future: _plansFuture,
        builder: (context, plansSnapshot) {
          if (plansSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (plansSnapshot.hasError) {
            return Center(child: Text('Error: ${plansSnapshot.error}'));
          }

          final allPlans = plansSnapshot.data ?? [];

          return StreamBuilder<List<UserPlanProgress>>(
            stream: _planService.getActivePlans(user.uid),
            builder: (context, progressSnapshot) {
              if (progressSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final activeProgress = progressSnapshot.data ?? [];

              final activePlansData = activeProgress.map((progress) {
                final plan = allPlans.firstWhere(
                  (p) => p.id == progress.planId,
                  orElse: () => ReadingPlan(
                      id: 'unknown',
                      title: 'Unknown Plan',
                      description: '',
                      durationDays: 0,
                      tags: [],
                      schedule: []),
                );
                return (plan: plan, progress: progress);
              }).where((item) => item.plan.id != 'unknown').toList();

              final discoverPlans = allPlans
                  .where((p) => !activeProgress.any((ap) => ap.planId == p.id))
                  .toList();

              return SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 100), // Space for FAB
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Active Plans Section
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Active Plans',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '${activePlansData.length} Ongoing',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (activePlansData.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('No active plans.'),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: activePlansData.map((data) {
                            final plan = data.plan;
                            final progress = data.progress;
                            final completedCount = progress.completedDays.length;
                            final totalCount = plan.durationDays;
                            final percent = totalCount > 0 ? completedCount / totalCount : 0.0;
                            final percentString = '${(percent * 100).toInt()}%';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                                ),
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    plan.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    plan.description,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '$percentString complete',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                      Text(
                                        '$completedCount/$totalCount days',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value: percent,
                                      minHeight: 8,
                                      backgroundColor: colorScheme.surfaceContainerHighest,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton(
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
                                            backgroundColor: colorScheme.primaryContainer,
                                            foregroundColor: colorScheme.onPrimaryContainer,
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: const Text(
                                            'Continue Reading',
                                            style: TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      OutlinedButton(
                                        onPressed: () => _leavePlan(plan),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: colorScheme.onSurfaceVariant,
                                          side: BorderSide(
                                            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                                          ),
                                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Text(
                                          'Leave',
                                          style: TextStyle(fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                    // Discover New Plans Section
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Discover New Plans',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              // Implement see all if needed
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: colorScheme.primary,
                              textStyle: const TextStyle(fontWeight: FontWeight.w600),
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('See All'),
                          ),
                        ],
                      ),
                    ),

                    if (discoverPlans.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('No new plans available right now.'),
                      )
                    else
                      SizedBox(
                        height: 180,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: discoverPlans.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 16),
                          itemBuilder: (context, index) {
                            final plan = discoverPlans[index];
                            return Container(
                              width: 260,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                                ),
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    plan.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Expanded(
                                    child: Text(
                                      plan.description,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${plan.durationDays} Days',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      FilledButton(
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
                                          backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
                                          foregroundColor: colorScheme.primary,
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                                          minimumSize: const Size(0, 36),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        child: const Text(
                                          'Enroll',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CreatePlanPage(
                firestore: widget.firestore,
                auth: widget.auth,
              ),
            ),
          );
        },
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 4,
        tooltip: 'Create New Plan',
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/reading_plan.dart';
import '../../models/reading_plan_progress.dart';
import '../../pages/plan_detail_page.dart';
import '../../services/reading_plan_service.dart';

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
  late Stream<List<UserPlanProgress>> _archivedPlansStream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _planService = ReadingPlanService(firestore: widget.firestore);

    final user = widget.auth.currentUser;
    _allPlansFuture = _planService.getAvailablePlans(userId: user?.uid);

    if (user != null) {
      _activePlansStream = _planService.getActivePlans(user.uid);
      _archivedPlansStream = _planService.getArchivedPlans(user.uid);
    } else {
      _activePlansStream = Stream.value([]);
      _archivedPlansStream = Stream.value([]);
    }
  }

  void _showLeavePlanDialog(ReadingPlan plan) {
    final user = widget.auth.currentUser;
    if (user == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Leave "${plan.title}"?'),
        content: const Text(
            'Would you like to archive this plan to keep your progress, or delete it permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _archivePlan(plan);
            },
            child: const Text('Archive'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePlanPermanently(plan);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  void _archivePlan(ReadingPlan plan) {
    final user = widget.auth.currentUser;
    if (user != null) {
      _planService.setPlanArchived(user.uid, plan.id, true).then((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${plan.title}" archived')),
          );
        }
      });
    }
  }

  void _unarchivePlan(ReadingPlan plan) {
    final user = widget.auth.currentUser;
    if (user != null) {
      _planService.setPlanArchived(user.uid, plan.id, false).then((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${plan.title}" restored to active')),
          );
        }
      });
    }
  }

  void _deletePlanPermanently(ReadingPlan plan) {
    final user = widget.auth.currentUser;
    if (user != null) {
      _planService.leavePlan(user.uid, plan.id).then((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${plan.title}" deleted permanently')),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;
    final user = widget.auth.currentUser;

    if (user == null) {
      return const Center(child: Text('Please log in to see your plans'));
    }

    return StreamBuilder<List<UserPlanProgress>>(
      stream: _activePlansStream,
      builder: (context, activeSnapshot) {
        final activeProgress = activeSnapshot.data ?? [];

        return StreamBuilder<List<UserPlanProgress>>(
          stream: _archivedPlansStream,
          builder: (context, archivedSnapshot) {
            final archivedProgress = archivedSnapshot.data ?? [];

            return FutureBuilder<List<ReadingPlan>>(
              future: _allPlansFuture,
              builder: (context, plansSnapshot) {
                if (plansSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allPlans = plansSnapshot.data ?? [];

                final activePlansData = activeProgress
                    .map((progress) {
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
                    })
                    .where((item) => item.plan.id != 'unknown')
                    .toList();

                final archivedPlansData = archivedProgress
                    .map((progress) {
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
                    })
                    .where((item) => item.plan.id != 'unknown')
                    .toList();

                return ListView(
                  padding: const EdgeInsets.only(bottom: 100),
                  children: [
                    // Active Plans Section
                    if (activePlansData.isNotEmpty) ...[
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
                                color: colorScheme.primaryContainer
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                '${activePlansData.length} Ongoing',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...activePlansData.map((data) => _buildActivePlanCard(
                            context,
                            colorScheme,
                            data.plan,
                            data.progress,
                          )),
                    ],

                    // Archive Section
                    if (archivedPlansData.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Archive',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Text(
                              '${archivedPlansData.length} Plans',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...archivedPlansData.map((data) => _buildArchivedPlanCard(
                            context,
                            colorScheme,
                            data.plan,
                            data.progress,
                          )),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
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

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      padding: const EdgeInsets.all(20),
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
                  fontWeight: FontWeight.bold,
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
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Continue Reading',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => _showLeavePlanDialog(plan),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.onSurfaceVariant,
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Leave',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildArchivedPlanCard(
    BuildContext context,
    ColorScheme colorScheme,
    ReadingPlan plan,
    UserPlanProgress progress,
  ) {
    final completedCount = progress.completedDays.length;
    final totalCount = plan.durationDays;
    final percent = totalCount > 0 ? completedCount / totalCount : 0.0;
    final percentString = '${(percent * 100).toInt()}%';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.1),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$percentString complete ($completedCount/$totalCount days)',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _unarchivePlan(plan),
            icon: const Icon(Icons.restore),
            tooltip: 'Unarchive and continue',
            color: colorScheme.primary,
          ),
          IconButton(
            onPressed: () => _deletePlanPermanently(plan),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete permanently',
            color: Colors.red.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/group.dart';
import '../../models/group_member_progress.dart';
import '../../models/group_schedule.dart';
import '../../services/group_service.dart';
import '../../services/vibration_service.dart';
import '../../services/catch_up_engine.dart';
import '../../theme/app_theme.dart';
import '../../pages/group_detail_page.dart';
import '../../pages/full_schedule_page.dart';
import '../../pages/group_catch_up_page.dart';
import '../catch_up_status_row.dart';
import '../common_styles.dart';

class CommunityGroupProgressCard extends StatelessWidget {
  final Group group;
  final GroupService groupService;
  final FirebaseAuth auth;
  final User user;
  final VibrationService vibrationService;
  final List<GroupSchedule>? initialSchedule;
  final List<GroupMemberProgressData>? initialProgress;

  const CommunityGroupProgressCard({
    super.key,
    required this.group,
    required this.groupService,
    required this.auth,
    required this.user,
    required this.vibrationService,
    this.initialSchedule,
    this.initialProgress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(boxShadow: AppSpacing.cardShadow(context)),
      child: Material(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            vibrationService.lightImpact();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GroupDetailPage(
                  group: group,
                  groupService: groupService,
                  auth: auth,
                  vibrationService: vibrationService,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Group Icon
                    Container(
                      width: 80,
                      height: 100,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.2,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: theme.shadowColor.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          Icons.groups,
                          size: 36,
                          color: colorScheme.primary.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: StreamBuilder<List<GroupSchedule>>(
                        stream: groupService.schedule(group.id),
                        initialData: initialSchedule,
                        builder: (context, scheduleSnap) {
                          final schedule = scheduleSnap.data ?? [];
                          // Calculate days
                          final now = DateTime.now();
                          final today = DateTime(now.year, now.month, now.day);

                          int currentDay = 0;
                          final totalDays = schedule.length;

                          if (schedule.isNotEmpty) {
                            // Find index of today or next upcoming
                            final index = schedule.indexWhere(
                              (s) => !s.date.isBefore(today),
                            );
                            if (index != -1) {
                              if (schedule[index].date.isAtSameMomentAs(
                                    today,
                                  )) {
                                currentDay = index + 1;
                              } else {
                                currentDay = index + 1; // Upcoming
                              }
                            } else {
                              // All in past
                              currentDay = totalDays;
                            }
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.name,
                                style: AppTextStyles.title(
                                  context,
                                ).copyWith(fontSize: 18),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
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
                                      'Day $currentDay',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'of $totalDays • Collective Plan',
                                    style: AppTextStyles.body(context).copyWith(
                                      fontSize: 11,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              StreamBuilder<List<GroupMemberProgressData>>(
                                stream: groupService.memberOverallCompletion(
                                  group.id,
                                  includeUid: user.uid,
                                ),
                                initialData: initialProgress,
                                builder: (context, progressSnap) {
                                  final members = progressSnap.data ?? [];
                                  final myProgress = members.firstWhere(
                                    (m) => m.uid == user.uid,
                                    orElse: () => GroupMemberProgressData(
                                      uid: '',
                                      name: '',
                                      completion: 0.0,
                                    ),
                                  );
                                  final percent = myProgress.completion;

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '${(percent * 100).toInt()}% of Schedule',
                                            style: AppTextStyles.body(context)
                                                .copyWith(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: LinearProgressIndicator(
                                          value: percent,
                                          minHeight: 8,
                                          backgroundColor: colorScheme
                                              .surfaceContainerHighest,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Group catch-up status row — gentle behind/on-track state for
                // the user's progress against the shared schedule (issue #720).
                StreamBuilder<List<GroupSchedule>>(
                  stream: groupService.schedule(group.id),
                  initialData: initialSchedule,
                  builder: (context, scheduleSnap) {
                    final schedule = scheduleSnap.data ?? [];
                    if (schedule.isEmpty) return const SizedBox.shrink();
                    return StreamBuilder<Map<String, int>>(
                      stream: groupService.userProgressForGroup(
                        group.id,
                        user.uid,
                      ),
                      builder: (context, progressSnap) {
                        final completed = (progressSnap.data ?? {})
                            .entries
                            .where((e) => e.value > 0)
                            .map((e) => e.key)
                            .toSet();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: CatchUpStatusRow(
                            status: CatchUpEngine.forGroupSchedule(
                              schedule,
                              completed,
                              today: DateTime.now(),
                            ),
                            onTrackLabel: 'In step with your group',
                            onTap: () {
                              vibrationService.lightImpact();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => FullSchedulePage(
                                    group: group,
                                    groupService: groupService,
                                    auth: auth,
                                    vibrationService: vibrationService,
                                    initialSchedule: initialSchedule,
                                    isMember: true,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            vibrationService.lightImpact();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => FullSchedulePage(
                                  group: group,
                                  groupService: groupService,
                                  auth: auth,
                                  vibrationService: vibrationService,
                                  initialSchedule: initialSchedule,
                                  isMember: true,
                                ),
                              ),
                            );
                          },
                          icon: Icon(
                            Icons.calendar_today,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                          label: Text(
                            'Schedule',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: colorScheme.primary,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: colorScheme.primary.withValues(alpha: 0.3),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: FilledButton.icon(
                          onPressed: () {
                            vibrationService.lightImpact();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => GroupCatchUpPage(
                                  group: group,
                                  groupService: groupService,
                                  auth: auth,
                                  vibrationService: vibrationService,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.history_rounded, size: 18),
                          label: const Text(
                            'Log Progress',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: colorScheme.primaryContainer,
                            foregroundColor: colorScheme.onPrimaryContainer,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

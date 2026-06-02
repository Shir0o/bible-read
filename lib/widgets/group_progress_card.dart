import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/group.dart';
import '../models/group_member_progress.dart';
import '../models/group_schedule.dart';
import '../services/group_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../pages/full_schedule_page.dart';

/// A card that displays the overall progress of a reading group.
class GroupProgressCard extends StatelessWidget {
  final String groupId;
  final List<GroupSchedule> schedule;
  final GroupService groupService;
  final DateTime currentDate;
  final Group? group; // Optional group model for navigation
  final FirebaseAuth? auth;
  final VibrationService? vibrationService;

  const GroupProgressCard({
    super.key,
    required this.groupId,
    required this.schedule,
    required this.groupService,
    required this.currentDate,
    this.group,
    this.auth,
    this.vibrationService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Calculate time-based expected progress
    int totalChapters = 0;
    int expectedCompletedChapters = 0;
    final today = DateTime(
      currentDate.year,
      currentDate.month,
      currentDate.day,
    );

    String? currentBook;

    for (var s in schedule) {
      totalChapters += s.chapters.length;
      if (s.date.isBefore(today) || s.date.isAtSameMomentAs(today)) {
        expectedCompletedChapters += s.chapters.length;
      }
      if (s.date.isAtSameMomentAs(today) && s.chapters.isNotEmpty) {
        // Simple parsing: assuming format "Book Chapter"
        final firstChapter = s.chapters.first;
        final parts = firstChapter.split(' ');
        if (parts.length > 1) {
          // Handle "1 John" cases
          if (int.tryParse(parts[0]) != null && parts.length > 2) {
            currentBook = '${parts[0]} ${parts[1]}';
          } else {
            currentBook = parts[0];
          }
        } else {
          currentBook = parts[0];
        }
      }
    }

    final timePercent =
        totalChapters > 0 ? expectedCompletedChapters / totalChapters : 0.0;

    return StreamBuilder<List<GroupMemberProgressData>>(
      stream: groupService.memberOverallCompletion(groupId),
      builder: (context, snapshot) {
        final members = snapshot.data ?? [];
        final double actualPercent = members.isEmpty
            ? 0.0
            : members.map((m) => m.completion).reduce((a, b) => a + b) /
                members.length;

        final percentDisplay = (actualPercent * 100).round();
        final bool isOnTrack = actualPercent >= timePercent;

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppSpacing.cardShadow(context),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('GROUP PROGRESS', style: theme.textTheme.labelSmall),
                      const SizedBox(height: 4),
                      Text(
                        '$percentDisplay%',
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isOnTrack
                          ? colorScheme.primaryContainer
                          : colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isOnTrack ? 'On Track' : 'Behind',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isOnTrack
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: actualPercent,
                  minHeight: 16,
                  backgroundColor: colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.2,
                  ),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                currentBook != null
                    ? 'The group is $percentDisplay% through the Book of $currentBook.'
                    : 'The group is $percentDisplay% through the reading plan.',
                style: theme.textTheme.bodyMedium,
              ),
              if (group != null && auth != null) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      vibrationService?.lightImpact();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FullSchedulePage(
                            group: group!,
                            groupService: groupService,
                            auth: auth!,
                            vibrationService:
                                vibrationService ?? const VibrationService(),
                            isMember: true,
                          ),
                        ),
                      );
                    },
                    icon: Icon(
                      Icons.calendar_month,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    label: Text(
                      'View Full Schedule',
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
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

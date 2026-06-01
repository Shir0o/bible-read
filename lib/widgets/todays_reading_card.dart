import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/group_schedule.dart';
import '../services/group_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';

/// A card that displays the reading assignment for today and allows marking it as read.
class TodaysReadingCard extends StatelessWidget {
  final String groupId;
  final String userId;
  final GroupSchedule schedule;
  final GroupService groupService;
  final VibrationService vibrationService;
  final bool isMember;
  final DateTime currentDate;

  /// Optional override for the "read" state (optimistic UI).
  final bool? pendingReadOverride;

  /// Optional overrides for individual chapters (optimistic UI).
  final Map<int, bool>? pendingChapterOverrides;

  /// Callback when the user toggles the read status.
  final Function({
    required bool read,
    required Set<int> currentlyChecked,
    required bool hasChapters,
  }) onToggle;

  /// Callback to notify the parent of latest snapshots for its own logic.
  final Function({
    required Set<int> rawChecked,
    required bool baseDone,
    required int totalChapters,
  })? onSnapshotsUpdated;

  const TodaysReadingCard({
    super.key,
    required this.groupId,
    required this.userId,
    required this.schedule,
    required this.groupService,
    required this.vibrationService,
    required this.isMember,
    required this.currentDate,
    required this.onToggle,
    this.pendingReadOverride,
    this.pendingChapterOverrides,
    this.onSnapshotsUpdated,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final dateString = _formatDate(currentDate);
    final readingTitle = schedule.chapters.join(', ');

    final dateKey = _dateKey(schedule.date);
    final entryRef = groupService.firestore
        .collection('groups')
        .doc(groupId)
        .collection('progress')
        .doc(dateKey)
        .collection('entries')
        .doc(userId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Today's Reading", style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
            ),
            boxShadow: AppSpacing.cardShadow(context),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(dateString, style: theme.textTheme.labelSmall),
              const SizedBox(height: 8),
              Text(
                readingTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              if (isMember)
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: entryRef.snapshots(),
                  builder: (context, entrySnap) {
                    final entryData = entrySnap.data?.data();
                    final baseDone = entryData?['done'] == true;

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: entryRef.collection('items').snapshots(),
                      builder: (context, itemsSnap) {
                        final rawChecked = <int>{};
                        for (final d in itemsSnap.data?.docs ?? const []) {
                          final idx = int.tryParse(d.id);
                          if (idx != null) rawChecked.add(idx);
                        }

                        final rawCheckedSnapshot = Set<int>.from(rawChecked);
                        final totalChapters = schedule.chapters.length;
                        final hasChapters = totalChapters > 0;

                        // Notify parent of latest snapshots
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          onSnapshotsUpdated?.call(
                            rawChecked: rawCheckedSnapshot,
                            baseDone: baseDone,
                            totalChapters: totalChapters,
                          );
                        });

                        // Determine effective read status
                        final isRead = hasChapters
                            ? (pendingReadOverride ??
                                (totalChapters > 0 &&
                                    rawCheckedSnapshot.length >= totalChapters))
                            : (pendingReadOverride ?? baseDone);

                        return SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              vibrationService.lightImpact();
                              onToggle(
                                read: !isRead,
                                currentlyChecked: rawCheckedSnapshot,
                                hasChapters: hasChapters,
                              );
                            },
                            icon: Icon(
                              Icons.check_circle,
                              color: isRead
                                  ? colorScheme.onPrimary
                                  : colorScheme.onPrimary.withValues(
                                      alpha: 0.7,
                                    ),
                              fill: isRead ? 1.0 : 0.0,
                            ),
                            label: Text(isRead ? 'Read' : 'Mark as Read'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isRead
                                  ? colorScheme.primary
                                  : colorScheme.primary.withValues(alpha: 0.8),
                              foregroundColor: colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              elevation: isRead ? 0 : 4,
                              textStyle: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 16,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

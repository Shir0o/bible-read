import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/group.dart';
import '../../models/group_member_progress.dart';
import '../../models/group_schedule.dart';
import '../../services/group_service.dart';
import '../../services/vibration_service.dart';
import '../../theme/app_theme.dart';
import '../common_styles.dart';
import '../member_presence_stack.dart';

/// The "community's reading" hero — the centrepiece of the Community tab
/// (design: `circle.jsx`). Leads with today's shared passage, who has shown up,
/// the group's progress, and a one-tap "Read with the community" action.
class CommunityReadingHero extends StatefulWidget {
  final Group group;
  final GroupService groupService;
  final User user;
  final VibrationService vibrationService;
  final DateTime Function() dateProvider;
  final List<GroupSchedule>? initialSchedule;

  const CommunityReadingHero({
    super.key,
    required this.group,
    required this.groupService,
    required this.user,
    required this.vibrationService,
    required this.dateProvider,
    this.initialSchedule,
  });

  @override
  State<CommunityReadingHero> createState() => _CommunityReadingHeroState();
}

class _CommunityReadingHeroState extends State<CommunityReadingHero> {
  /// Optimistic override for the current user's "read today" state.
  bool? _pendingRead;
  bool _busy = false;

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  GroupSchedule? _todayEntry(List<GroupSchedule> schedule) {
    final key = _ymd(widget.dateProvider());
    for (final s in schedule) {
      if (_ymd(s.date) == key) return s;
    }
    return null;
  }

  Future<void> _toggle(GroupSchedule today, bool currentlyRead) async {
    if (_busy) return;
    widget.vibrationService.lightImpact();
    setState(() {
      _busy = true;
      _pendingRead = !currentlyRead;
    });
    final ok = await widget.groupService.toggleReadStatus(
      groupId: widget.group.id,
      uid: widget.user.uid,
      schedule: today,
      read: !currentlyRead,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _pendingRead = currentlyRead; // revert on failure
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);

    return StreamBuilder<List<GroupSchedule>>(
      stream: widget.groupService.schedule(widget.group.id),
      initialData: widget.initialSchedule,
      builder: (context, schedSnap) {
        final schedule = schedSnap.data ?? const <GroupSchedule>[];
        final today = _todayEntry(schedule);
        final chapters = today?.chapters ?? const <String>[];

        return StreamBuilder<List<GroupMemberProgressData>>(
          stream: widget.groupService.memberDailyCompletion(
            widget.group.id,
            includeUid: widget.user.uid,
          ),
          builder: (context, progSnap) {
            final members = progSnap.data ?? const <GroupMemberProgressData>[];
            final total = members.length;
            final readers = members.where((m) => m.completion >= 1.0).toList();
            double myCompletion = 0;
            for (final m in members) {
              if (m.uid == widget.user.uid) {
                myCompletion = m.completion;
                break;
              }
            }
            final serverRead = myCompletion >= 1.0;
            final meRead = _pendingRead ?? serverRead;
            // Count "me" optimistically so the meter and CTA agree.
            final readCount =
                (readers.where((m) => m.uid != widget.user.uid)).length +
                    (meRead ? 1 : 0);

            return Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: appColors.primarySoft,
                borderRadius: BorderRadius.circular(AppSpacing.rCard),
                border: Border.all(color: appColors.primaryLine),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "THE COMMUNITY'S READING",
                          style: AppTextStyles.caption(context).copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      if (readers.isNotEmpty)
                        MemberPresenceStack(members: readers, size: 28, max: 4),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    chapters.isEmpty ? 'Rest day' : chapters.join(' · '),
                    style: AppTextStyles.title(context).copyWith(
                      fontSize: 32,
                      fontWeight: FontWeight.w500,
                      height: 1.0,
                      letterSpacing: -0.3,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.groups_outlined,
                        size: 15,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          widget.group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall(context).copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (total > 0) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: total == 0 ? 0 : readCount / total,
                              minHeight: 7,
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '$readCount of $total read',
                          style: AppTextStyles.bodySmall(context).copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildCta(context, today, chapters.isEmpty, meRead),
                  const SizedBox(height: 13),
                  Container(
                    padding: const EdgeInsets.only(top: 13),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: appColors.primaryLine),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.explore_outlined,
                          size: 14,
                          color: colorScheme.outline,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'Separate from your personal path on Journey.',
                            style: AppTextStyles.caption(context).copyWith(
                              color: colorScheme.onSurfaceVariant,
                              letterSpacing: 0,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCta(
    BuildContext context,
    GroupSchedule? today,
    bool noReading,
    bool meRead,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);

    if (noReading || today == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 15),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: appColors.primaryLine),
        ),
        child: Text(
          'No reading scheduled today — enjoy the pause.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall(context).copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (meRead) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: appColors.primaryLine),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primary,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 18,
                color: colorScheme.onPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'You read with the community today.',
                style: AppTextStyles.body(context).copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => _toggle(today, true),
              child: const Text('Undo'),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: _busy ? null : () => _toggle(today, false),
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : const Icon(Icons.check_rounded, size: 19),
        label: const Text('Read with the community'),
      ),
    );
  }
}

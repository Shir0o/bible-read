import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../pages/streak_history_page.dart';
import '../../theme/app_theme.dart';
import '../skeleton_loader.dart';
import '../skeletons/consistency_card_skeleton.dart';
import 'consistency_calendar.dart';

/// The Path tab's Consistency section: the current streak and the days shown
/// up this month above the calendar. The whole card opens streak history.
class ConsistencyCard extends StatelessWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final bool loading;
  final int streak;
  final Set<DateTime>? readDates;
  final DateTime now;

  const ConsistencyCard({
    super.key,
    required this.firestore,
    required this.auth,
    required this.loading,
    required this.streak,
    required this.readDates,
    required this.now,
  });

  static const _months = [
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

  static String _days(int n) => '$n ${n == 1 ? 'day' : 'days'}';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SkeletonLoader(
      loading: loading,
      minTime: const Duration(milliseconds: 1000),
      skeleton: const ConsistencyCardSkeleton(),
      child: Padding(
        padding: AppSpacing.horizontal,
        child: Material(
          color: colorScheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.rCard),
            side: BorderSide(color: AppColors.of(context).border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    StreakHistoryPage(auth: auth, firestore: firestore),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _Figure(
                          value: _days(streak),
                          label: 'Current streak',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.gap12),
                      Expanded(
                        child: _Figure(
                          value: _days(readDates?.length ?? 0),
                          label: 'Shown up in ${_months[now.month - 1]}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.gap16),
                  ConsistencyCalendar(
                    firestore: firestore,
                    auth: auth,
                    initialReadDates: readDates,
                    showTitle: false,
                    embedded: true,
                  ),
                  const SizedBox(height: AppSpacing.gap8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Streak history',
                          style: textTheme.labelLarge?.copyWith(
                            color: colorScheme.primary,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: AppSpacing.iconMd,
                          color: colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String value;
  final String label;

  const _Figure({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.gap4),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

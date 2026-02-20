import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class ConsistencyCalendar extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  const ConsistencyCalendar({
    super.key,
    required this.firestore,
    required this.auth,
  });

  @override
  State<ConsistencyCalendar> createState() => _ConsistencyCalendarState();
}

class _ConsistencyCalendarState extends State<ConsistencyCalendar> {
  DateTime _currentMonth = DateTime.now();
  Set<DateTime> _readDates = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    _loadStats();
  }

  void _changeMonth(int delta) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + delta, 1);
    });
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final start = DateTime(_currentMonth.year, _currentMonth.month, 1);
      final end = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);

      final readDates = await _queryRange(widget.firestore.collection('users').doc(uid), start, end);

      if (mounted) {
        setState(() {
          _readDates = readDates;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading stats: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // Adapted from StreakHistoryView
  Future<Set<DateTime>> _queryRange(
    DocumentReference<Map<String, dynamic>> userDocRef,
    DateTime start,
    DateTime end,
  ) async {
    final readingCollection = userDocRef.collection('reading');
    final startKey =
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final endKey =
        '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';

    final querySnapshot = await readingCollection
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: startKey)
        .where(FieldPath.documentId, isLessThanOrEqualTo: endKey)
        .get();

    final readingDataMap = {
      for (var doc in querySnapshot.docs) doc.id: doc.data()
    };

    final result = <DateTime>{};
    final dates = <DateTime>[];
    final uid = userDocRef.id;
    final fallbacks = <Future<DocumentSnapshot<Map<String, dynamic>>>>[];
    final fallbackIdx = <int>[];

    final totalDays = end.difference(start).inDays;
    for (int offset = 0; offset <= totalDays; offset++) {
      final day = DateTime(start.year, start.month, start.day + offset);
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      dates.add(day);

      if (readingDataMap.containsKey(key) &&
          readingDataMap[key]?['read'] == true) {
        result.add(day);
      } else {
        fallbacks.add(
          widget.firestore
              .collection('read_logs')
              .doc(key)
              .collection('entries')
              .doc(uid)
              .get(),
        );
        fallbackIdx.add(dates.length - 1);
      }
    }

    if (fallbacks.isNotEmpty) {
      final fbSnaps = await Future.wait(fallbacks);
      for (int j = 0; j < fbSnaps.length; j++) {
        if (fbSnaps[j].exists) {
          result.add(dates[fallbackIdx[j]]);
        }
      }
    }
    return result;
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return months[month - 1];
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isCurrentMonth = now.year == _currentMonth.year && now.month == _currentMonth.month;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.hPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Consistency',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_monthName(_currentMonth.month)} ${_currentMonth.year}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () => _changeMonth(-1),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: isCurrentMonth ? null : () => _changeMonth(1),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Days of week
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: ['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((day) {
                    return SizedBox(
                      width: 32,
                      child: Center(
                        child: Text(
                          day,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),

                // Calendar Grid
                _buildCalendarGrid(colorScheme),

                const SizedBox(height: 16),

                // Legend
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildLegendItem(
                      colorScheme,
                      label: 'Missed',
                      color: Colors.transparent,
                      borderColor: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 16),
                    _buildLegendItem(
                      colorScheme,
                      label: 'Read',
                      color: colorScheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24), // Bottom padding
        ],
      ),
    );
  }

  Widget _buildLegendItem(ColorScheme colorScheme, {required String label, required Color color, Color? borderColor}) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: borderColor != null ? Border.all(color: borderColor) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarGrid(ColorScheme colorScheme) {
    if (_loading) {
       return const SizedBox(
         height: 200,
         child: Center(child: CircularProgressIndicator()),
       );
    }

    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final weekdayOffset = firstDay.weekday % 7;

    // Previous month filler
    final prevMonthDays = DateTime(_currentMonth.year, _currentMonth.month, 0).day;

    final widgets = <Widget>[];

    // Previous month days
    for (int i = 0; i < weekdayOffset; i++) {
       final dayNum = prevMonthDays - weekdayOffset + i + 1;
       widgets.add(
         SizedBox(
           width: 32,
           height: 32,
           child: Center(
             child: Text(
               '$dayNum',
               style: TextStyle(
                 color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                 fontSize: 12,
               ),
             ),
           ),
         ),
       );
    }

    // Current month days
    for (int i = 1; i <= daysInMonth; i++) {
      final date = DateTime(_currentMonth.year, _currentMonth.month, i);
      final isRead = _readDates.any((d) => _isSameDay(d, date));
      final isToday = _isSameDay(DateTime.now(), date);

      widgets.add(
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isRead ? colorScheme.primary : Colors.transparent,
            border: isToday && !isRead
                ? Border.all(color: colorScheme.primary.withValues(alpha: 0.5))
                : null,
          ),
          child: Center(
            child: Text(
              '$i',
              style: TextStyle(
                color: isRead
                    ? colorScheme.onPrimary
                    : (isToday ? colorScheme.primary : colorScheme.onSurface),
                fontSize: 12,
                fontWeight: isRead || isToday ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }

    // Next month days (fill row)
    final remainingCells = 7 - (widgets.length % 7);
    if (remainingCells < 7) {
      for (int i = 1; i <= remainingCells; i++) {
         widgets.add(
           SizedBox(
             width: 32,
             height: 32,
             child: Center(
               child: Text(
                 '$i',
                 style: TextStyle(
                   color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                   fontSize: 12,
                 ),
               ),
             ),
           ),
         );
      }
    }

    return Wrap(
      spacing: (MediaQuery.of(context).size.width - (AppSpacing.hPadding * 2) - 40 - (32 * 7)) / 6, // Dynamic spacing? No, just use MainAxisAlignment.spaceBetween logic in a Grid/Wrap
      // Actually Wrap spacing is fixed.
      // Better to use a GridView or Table.
      // Table works well for calendar.
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      children: widgets,
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../skeleton.dart';
import '../../theme/app_theme.dart';
import '../../widgets/skeletons/consistency_calendar_skeleton.dart';
import '../skeleton_loader.dart';
import '../../services/reading_status_service.dart';

class ConsistencyCalendar extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final bool showTitle;
  final bool isLoading;
  final Set<DateTime>? initialReadDates;

  const ConsistencyCalendar({
    super.key,
    required this.firestore,
    required this.auth,
    this.showTitle = true,
    this.isLoading = false,
    this.initialReadDates,
  });

  @override
  State<ConsistencyCalendar> createState() => _ConsistencyCalendarState();
}

class _ConsistencyCalendarState extends State<ConsistencyCalendar> {
  DateTime _currentMonth = DateTime.now();
  Set<DateTime> _readDates = {};
  bool _loading = false;
  late final ReadingStatusService _readingStatusService;

  @override
  void initState() {
    super.initState();
    _readingStatusService = ReadingStatusService(
      firestore: widget.firestore,
      auth: widget.auth,
    );
    _currentMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);

    if (widget.initialReadDates != null) {
      _readDates = widget.initialReadDates!;
    } else {
      _loadStats();
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _currentMonth = DateTime(
        _currentMonth.year,
        _currentMonth.month + delta,
        1,
      );
    });
    _loadStats();
  }

  Future<void> _loadStats() async {
    if (mounted) setState(() => _loading = true);
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final daysInMonth = DateTime(
        _currentMonth.year,
        _currentMonth.month + 1,
        0,
      ).day;

      final statusMap = await _readingStatusService.getReadStatusForRange(
        uid,
        daysInMonth,
        referenceDate: DateTime(
          _currentMonth.year,
          _currentMonth.month,
          daysInMonth,
        ),
      );

      final readDates = statusMap.entries
          .where((e) => e.value)
          .map((e) => DateTime.parse(e.key))
          .toSet();

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

  // Removed _queryRange as it's now in ReadingStatusService

  String _monthName(int month) {
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
    return months[month - 1];
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isCurrentMonth =
        now.year == _currentMonth.year && now.month == _currentMonth.month;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.hPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showTitle) ...[
            Text(
              'Showing up',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
            ),
            const SizedBox(height: 12),
          ],
          SkeletonLoader(
            loading: widget.isLoading,
            minTime: const Duration(milliseconds: 1000),
            skeleton: const ConsistencyCalendarSkeleton(),
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppSpacing.rCard),
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
                            tooltip: 'Previous month',
                            onPressed: () => _changeMonth(-1),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            tooltip: 'Next month',
                            onPressed:
                                isCurrentMonth ? null : () => _changeMonth(1),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

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
                        borderColor: colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
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
          ),
          const SizedBox(height: 24), // Bottom padding
        ],
      ),
    );
  }

  Widget _buildLegendItem(
    ColorScheme colorScheme, {
    required String label,
    required Color color,
    Color? borderColor,
  }) {
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
      return Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          // Header row
          TableRow(
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
          const TableRow(
            children: [
              SizedBox(height: 8),
              SizedBox(height: 8),
              SizedBox(height: 8),
              SizedBox(height: 8),
              SizedBox(height: 8),
              SizedBox(height: 8),
              SizedBox(height: 8),
            ],
          ),
          // Skeleton rows
          for (int i = 0; i < 5; i++)
            TableRow(
              children: List.generate(7, (index) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Skeleton(width: 32, height: 32, radius: 16),
                  ),
                );
              }),
            ),
        ],
      );
    }

    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final daysInMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + 1,
      0,
    ).day;
    final weekdayOffset = firstDay.weekday % 7;

    // Previous month filler
    final prevMonthDays = DateTime(
      _currentMonth.year,
      _currentMonth.month,
      0,
    ).day;

    final cells = <Widget>[];

    // Previous month days
    for (int i = 0; i < weekdayOffset; i++) {
      final dayNum = prevMonthDays - weekdayOffset + i + 1;
      cells.add(
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

      cells.add(
        Semantics(
          label:
              '${_monthName(_currentMonth.month)} $i, ${_currentMonth.year}, ${isRead ? "Read" : "Missed"}${isToday ? " (Today)" : ""}',
          excludeSemantics: true,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            alignment: Alignment.center,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isRead ? colorScheme.primary : Colors.transparent,
                border: isToday && !isRead
                    ? Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.5),
                      )
                    : null,
              ),
              child: Center(
                child: Text(
                  '$i',
                  style: TextStyle(
                    color: isRead
                        ? colorScheme.onPrimary
                        : (isToday
                            ? colorScheme.primary
                            : colorScheme.onSurface),
                    fontSize: 12,
                    fontWeight:
                        isRead || isToday ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Next month days (fill row)
    final remainingCells = 7 - (cells.length % 7);
    if (remainingCells < 7) {
      for (int i = 1; i <= remainingCells; i++) {
        cells.add(
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

    final rows = <TableRow>[];

    // Header Row
    rows.add(
      TableRow(
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
    );

    // Spacer Row
    rows.add(
      const TableRow(
        children: [
          SizedBox(height: 8),
          SizedBox(height: 8),
          SizedBox(height: 8),
          SizedBox(height: 8),
          SizedBox(height: 8),
          SizedBox(height: 8),
          SizedBox(height: 8),
        ],
      ),
    );

    // Day Rows
    for (int i = 0; i < cells.length; i += 7) {
      final rowCells = cells.sublist(i, i + 7);
      rows.add(
        TableRow(
          children: rowCells.map((cell) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: cell,
              ),
            );
          }).toList(),
        ),
      );
    }

    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: rows,
    );
  }
}

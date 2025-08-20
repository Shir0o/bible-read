import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/common_styles.dart';
import '../widgets/menu_button.dart';
import '../widgets/streak_stats_box.dart';
import '../widgets/week_streak_calendar.dart';
import '../widgets/month_streak_calendar.dart';
import '../services/error_logger.dart';

/// Displays the user's reading streak history.
class StreakHistoryPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  /// Creates a [StreakHistoryPage].
  StreakHistoryPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance;

  @override
  State<StreakHistoryPage> createState() => _StreakHistoryPageState();
}

enum _Period { week, month }

class _StreakHistoryPageState extends State<StreakHistoryPage> {
  _Period _period = _Period.week;
  late DateTime _periodStart;

  int _currentStreak = 0;
  int _longestStreak = 0;
  int _totalReadDays = 0;
  int _periodCount = 0;
  Set<DateTime> _readDates = {};

  @override
  void initState() {
    super.initState();
    _periodStart = _startOfWeek(DateTime.now());
    _loadStats();
  }

  DateTime _startOfWeek(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: date.weekday % 7));
  }

  DateTime _startOfMonth(DateTime date) => DateTime(date.year, date.month, 1);

  void _onPeriodChanged(Set<_Period> value) {
    final selection = value.first;
    setState(() {
      _period = selection;
      _periodStart = selection == _Period.week
          ? _startOfWeek(DateTime.now())
          : _startOfMonth(DateTime.now());
    });
    _loadStats();
  }

  void _changePeriod(int delta) {
    setState(() {
      if (_period == _Period.week) {
        _periodStart = _periodStart.add(Duration(days: 7 * delta));
      } else {
        _periodStart = DateTime(_periodStart.year, _periodStart.month + delta);
      }
    });
    _loadStats();
  }

  /// Loads streak statistics and read dates for the selected period.
  ///
  /// For the current week or month we first consult the cached arrays in the
  /// user's summary document. Those arrays may contain dates outside the
  /// requested window or may omit some days entirely. We therefore filter the
  /// cached dates to the current period and, if the remaining list doesn't cover
  /// every day, fall back to querying individual `reading` documents via
  /// [_queryRange].
  Future<void> _loadStats() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final userDocRef = widget.firestore.collection('users').doc(uid);
      final summaryDoc =
          await userDocRef.collection('summary').doc('data').get();
      final data = summaryDoc.data() ?? {};

      final now = DateTime.now();
      final bool isCurrentWeek =
          _period == _Period.week && _periodStart == _startOfWeek(now);
      final bool isCurrentMonth = _period == _Period.month &&
          _periodStart.year == now.year &&
          _periodStart.month == now.month;

      int currentStreak = data['streak'] ?? 0;
      int longestStreak = data['longestStreak'] ?? currentStreak;
      int totalReadDays = data['totalReadDays'] ?? 0;
      int periodCount = 0;
      Set<DateTime> readDates = {};

      if (isCurrentWeek) {
        final end = _periodStart.add(const Duration(days: 6));
        var dates = List<String>.from(data['pastWeekReadDates'] ?? []);
        // Keep only dates within the selected week. The summary cache may
        // contain stale entries so we filter them out first.
        dates = dates.where((d) {
          final parsed = DateTime.tryParse(d);
          return parsed != null &&
              !parsed.isBefore(_periodStart) &&
              !parsed.isAfter(end);
        }).toList();
        if (dates.length == 7) {
          // All seven days are present meaning the summary fully covers the
          // week, so we can trust it without hitting Firestore.
          final set = dates.toSet();
          for (int i = 0; i < 7; i++) {
            final day = _periodStart.add(Duration(days: i));
            final key =
                '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
            if (set.contains(key)) {
              periodCount++;
              readDates.add(day);
            }
          }
        } else {
          // If the filtered list doesn't include all days, fall back to
          // querying individual reading documents for an authoritative answer.
          readDates = await _queryRange(userDocRef, _periodStart, end);
          periodCount = readDates.length;
        }
      } else if (isCurrentMonth) {
        final end = DateTime(_periodStart.year, _periodStart.month + 1, 0);
        var dates = List<String>.from(data['pastMonthReadDates'] ?? []);
        // Apply the same windowing to the cached month data.
        dates = dates.where((d) {
          final parsed = DateTime.tryParse(d);
          return parsed != null &&
              !parsed.isBefore(_periodStart) &&
              !parsed.isAfter(end);
        }).toList();
        final daysInMonth = end.day;
        if (dates.length == daysInMonth) {
          // The summary has an entry for every day of the month.
          final set = dates.toSet();
          for (int i = 0; i < daysInMonth; i++) {
            final day = _periodStart.add(Duration(days: i));
            final key =
                '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
            if (set.contains(key)) {
              periodCount++;
              readDates.add(day);
            }
          }
        } else {
          // Otherwise query the backing documents to ensure we have complete
          // data for the month.
          readDates = await _queryRange(userDocRef, _periodStart, end);
          periodCount = readDates.length;
        }
      } else {
        final end = _period == _Period.week
            ? _periodStart.add(const Duration(days: 6))
            : DateTime(_periodStart.year, _periodStart.month + 1, 0);
        readDates = await _queryRange(userDocRef, _periodStart, end);
        periodCount = readDates.length;
      }

      if (!mounted) return;
      setState(() {
        _currentStreak = currentStreak;
        _longestStreak = longestStreak;
        _totalReadDays = totalReadDays;
        _periodCount = periodCount;
        _readDates = readDates;
      });
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  Future<Set<DateTime>> _queryRange(
    DocumentReference<Map<String, dynamic>> userDocRef,
    DateTime start,
    DateTime end,
  ) async {
    final readingCollection = userDocRef.collection('reading');
    final futures = <Future<DocumentSnapshot<Map<String, dynamic>>>>[];
    final dates = <DateTime>[];
    for (DateTime day = start;
        !day.isAfter(end);
        day = day.add(const Duration(days: 1))) {
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      futures.add(readingCollection.doc(key).get());
      dates.add(day);
    }
    final snaps = await Future.wait(futures);
    final result = <DateTime>{};
    for (int i = 0; i < snaps.length; i++) {
      if (snaps[i].data()?['read'] == true) {
        result.add(dates[i]);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final periodLabel = _period == _Period.week ? 'Week reads' : 'Month reads';

    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        'History',
        leading: const MenuButton(),
        automaticallyImplyLeading: false,
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SegmentedButton<_Period>(
                  segments: const [
                    ButtonSegment(value: _Period.week, label: Text('Week')),
                    ButtonSegment(value: _Period.month, label: Text('Month')),
                  ],
                  selected: {_period},
                  onSelectionChanged: _onPeriodChanged,
                ),
              ],
            ),
            StreakStatsBox(
              currentStreak: _currentStreak,
              longestStreak: _longestStreak,
              totalReadDays: _totalReadDays,
              periodCount: _periodCount,
              periodLabel: periodLabel,
            ),
            const SizedBox(height: 16),
            if (_period == _Period.week)
              WeekStreakCalendar(
                readDates: _readDates,
                sunday: _periodStart,
                onPrevious: () => _changePeriod(-1),
                onNext: () => _changePeriod(1),
              )
            else
              MonthStreakCalendar(
                readDates: _readDates,
                month: _periodStart,
                onPrevious: () => _changePeriod(-1),
                onNext: () => _changePeriod(1),
              ),
          ],
        ),
      ),
    );
  }
}

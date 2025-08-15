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
  }) : firestore = firestore ?? FirebaseFirestore.instance,
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

  Future<void> _loadStats() async {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final userDocRef = widget.firestore.collection('users').doc(uid);
      final summaryDoc = await userDocRef
          .collection('summary')
          .doc('data')
          .get();
      final data = summaryDoc.data() ?? {};

      final now = DateTime.now();
      final bool isCurrentWeek =
          _period == _Period.week && _periodStart == _startOfWeek(now);
      final bool isCurrentMonth =
          _period == _Period.month &&
          _periodStart.year == now.year &&
          _periodStart.month == now.month;

      int currentStreak = data['streak'] ?? 0;
      int longestStreak = data['longestStreak'] ?? currentStreak;
      int totalReadDays = data['totalReadDays'] ?? 0;
      int periodCount = 0;
      Set<DateTime> readDates = {};

      if (isCurrentWeek) {
        final dates = List<String>.from(data['pastWeekReadDates'] ?? []);
        if (dates.isNotEmpty) {
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
          readDates = await _queryRange(
            userDocRef,
            _periodStart,
            _periodStart.add(const Duration(days: 6)),
          );
          periodCount = readDates.length;
        }
      } else if (isCurrentMonth) {
        final dates = List<String>.from(data['pastMonthReadDates'] ?? []);
        if (dates.isNotEmpty) {
          final set = dates.toSet();
          final daysInMonth = DateTime(
            _periodStart.year,
            _periodStart.month + 1,
            0,
          ).day;
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
          final end = DateTime(_periodStart.year, _periodStart.month + 1, 0);
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
    for (
      DateTime day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
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

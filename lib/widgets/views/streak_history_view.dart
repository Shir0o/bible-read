import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../common_styles.dart';
import '../streak_stats_box.dart';
import '../week_streak_calendar.dart';
import '../month_streak_calendar.dart';
import '../../services/error_logger.dart';

class StreakHistoryView extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  const StreakHistoryView({
    super.key,
    required this.firestore,
    required this.auth,
  });

  @override
  State<StreakHistoryView> createState() => _StreakHistoryViewState();
}

enum _Period { week, month }

class _StreakHistoryViewState extends State<StreakHistoryView> {
  _Period _period = _Period.week;
  late DateTime _periodStart;

  int _currentStreak = 0;
  int _longestStreak = 0;
  int _totalReadDays = 0;
  int _periodCount = 0;
  int? _remainingGraceCredits;
  Set<DateTime> _readDates = {};

  @override
  void initState() {
    super.initState();
    _periodStart = _startOfWeek(DateTime.now());
    _loadStats();
  }

  DateTime _startOfWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final weekdayOffset = normalized.weekday % 7;
    return DateTime(
      normalized.year,
      normalized.month,
      normalized.day - weekdayOffset,
    );
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
        _periodStart = DateTime(
          _periodStart.year,
          _periodStart.month,
          _periodStart.day + (7 * delta),
        );
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
      final summaryDoc =
          await userDocRef.collection('summary').doc('data').get();
      final data = summaryDoc.data() ?? {};
      final now = DateTime.now();
      final currentMonthKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';
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
      int? remainingGraceCredits;

      if (data['graceCreditsMonth'] == currentMonthKey &&
          data['graceCreditsAvailable'] is int) {
        remainingGraceCredits = data['graceCreditsAvailable'] as int;
      }

      if (isCurrentWeek) {
        final end = DateTime(
          _periodStart.year,
          _periodStart.month,
          _periodStart.day + 6,
        );
        var dates = List<String>.from(data['pastWeekReadDates'] ?? []);
        dates = dates.where((d) {
          final parsed = DateTime.tryParse(d);
          return parsed != null &&
              !parsed.isBefore(_periodStart) &&
              !parsed.isAfter(end);
        }).toList();
        if (dates.length == 7) {
          final set = dates.toSet();
          for (int i = 0; i < 7; i++) {
            final day = DateTime(
              _periodStart.year,
              _periodStart.month,
              _periodStart.day + i,
            );
            final key =
                '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
            if (set.contains(key)) {
              periodCount++;
              readDates.add(day);
            }
          }
        } else {
          readDates = await _queryRange(userDocRef, _periodStart, end);
          periodCount = readDates.length;
        }
      } else if (isCurrentMonth) {
        final end = DateTime(_periodStart.year, _periodStart.month + 1, 0);
        var dates = List<String>.from(data['pastMonthReadDates'] ?? []);
        dates = dates.where((d) {
          final parsed = DateTime.tryParse(d);
          return parsed != null &&
              !parsed.isBefore(_periodStart) &&
              !parsed.isAfter(end);
        }).toList();
        final daysInMonth = end.day;
        if (dates.length == daysInMonth) {
          final set = dates.toSet();
          for (int i = 0; i < daysInMonth; i++) {
            final day = DateTime(
              _periodStart.year,
              _periodStart.month,
              _periodStart.day + i,
            );
            final key =
                '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
            if (set.contains(key)) {
              periodCount++;
              readDates.add(day);
            }
          }
        } else {
          readDates = await _queryRange(userDocRef, _periodStart, end);
          periodCount = readDates.length;
        }
      } else {
        final end = _period == _Period.week
            ? DateTime(
                _periodStart.year,
                _periodStart.month,
                _periodStart.day + 6,
              )
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
        _remainingGraceCredits = remainingGraceCredits;
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
    final keys = <String>[];
    final totalDays = end.difference(start).inDays;
    for (int offset = 0; offset <= totalDays; offset++) {
      final day = DateTime(start.year, start.month, start.day + offset);
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      futures.add(readingCollection.doc(key).get());
      dates.add(day);
      keys.add(key);
    }
    final snaps = await Future.wait(futures);
    final result = <DateTime>{};
    for (int i = 0; i < snaps.length; i++) {
      if (snaps[i].data()?['read'] == true) {
        result.add(dates[i]);
      }
    }

    final uid = userDocRef.id;
    final fallbacks = <Future<DocumentSnapshot<Map<String, dynamic>>>>[];
    final fallbackIdx = <int>[];
    for (int i = 0; i < dates.length; i++) {
      if (!result.contains(dates[i])) {
        fallbacks.add(
          widget.firestore
              .collection('read_logs')
              .doc(keys[i])
              .collection('entries')
              .doc(uid)
              .get(),
        );
        fallbackIdx.add(i);
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

  @override
  Widget build(BuildContext context) {
    final periodLabel = _period == _Period.week ? 'Week reads' : 'Month reads';

    return Scaffold(
      body: Container(
        decoration:
            CommonStyles.backgroundDecoration(Theme.of(context).colorScheme),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const SizedBox(height: 12),
              StreakStatsBox(
                currentStreak: _currentStreak,
                longestStreak: _longestStreak,
                totalReadDays: _totalReadDays,
                periodCount: _periodCount,
                periodLabel: periodLabel,
                remainingGraceCredits: _remainingGraceCredits,
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
      ),
    );
  }
}

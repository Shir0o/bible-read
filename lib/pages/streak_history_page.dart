import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/common_styles.dart';
import '../widgets/menu_button.dart';
import '../widgets/streak_stats_box.dart';

/// Displays the user's reading streak history.
class StreakHistoryPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  /// Creates a [StreakHistoryPage].
  const StreakHistoryPage({
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

    final snapshot = await widget.firestore
        .collection('users')
        .doc(uid)
        .collection('reading')
        .get();

    final readDates = <DateTime>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['read'] == true) {
        final parts = doc.id.split('-');
        if (parts.length == 3) {
          final dt = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );
          readDates.add(dt);
        }
      }
    }

    readDates.sort();
    final readSet = readDates.toSet();
    final total = readDates.length;

    // Current streak
    int streak = 0;
    DateTime current = DateTime.now();
    current = DateTime(current.year, current.month, current.day);
    while (readSet.contains(current)) {
      streak++;
      current = current.subtract(const Duration(days: 1));
    }

    // Longest streak
    int longest = 0;
    int temp = 0;
    DateTime? prev;
    for (final date in readDates) {
      if (prev != null && date.difference(prev).inDays == 1) {
        temp++;
      } else {
        temp = 1;
      }
      if (temp > longest) longest = temp;
      prev = date;
    }

    final periodEnd = _period == _Period.week
        ? _periodStart.add(const Duration(days: 6))
        : DateTime(_periodStart.year, _periodStart.month + 1, 0);

    final periodCount = readDates
        .where((d) => !d.isBefore(_periodStart) && !d.isAfter(periodEnd))
        .length;

    if (!mounted) return;
    setState(() {
      _currentStreak = streak;
      _longestStreak = longest;
      _totalReadDays = total;
      _periodCount = periodCount;
    });
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
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => _changePeriod(-1),
                ),
                SegmentedButton<_Period>(
                  segments: const [
                    ButtonSegment(value: _Period.week, label: Text('Week')),
                    ButtonSegment(value: _Period.month, label: Text('Month')),
                  ],
                  selected: {_period},
                  onSelectionChanged: _onPeriodChanged,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _changePeriod(1),
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
          ],
        ),
      ),
    );
  }
}

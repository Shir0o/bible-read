import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/common_styles.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  bool _disposed = false;
  bool _readToday = false;
  bool _toggleLoading = false;
  int _streak = 0;
  List<bool> _pastWeek = [];
  List<bool> _pastMonth = [];
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _loadReadStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final today = DateTime.now();
      final dateKey = '${today.year}-${today.month}-${today.day}';

      final userDocRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);
      final userDoc = await userDocRef.get();
      if (!userDoc.exists) {
        await userDocRef.set({
          'name': user.displayName ?? '',
          'email': user.email ?? '',
        });

        final friendsCollection = userDocRef.collection('friends');
        final friendRequestsSentCollection =
            userDocRef.collection('friendRequestsSent');

        // These can be created later when adding/accepting friends,
        // but you can prepopulate with empty docs or placeholders if needed:
        // Example: initialize placeholder if needed
        await friendsCollection.doc('init').set(
            {'status': 'placeholder', 'timestamp': Timestamp.now()},
            SetOptions(merge: true));
        await friendRequestsSentCollection.doc('init').set(
            {'status': 'placeholder', 'timestamp': Timestamp.now()},
            SetOptions(merge: true));
      }

      _toggleLoading = true;
      final doc = await userDocRef.collection('reading').doc(dateKey).get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final hasRead = data.containsKey('read') ? data['read'] : false;
        if (!_disposed && mounted) {
          setState(() {
            _readToday = hasRead;
            _toggleLoading = false;
          });
        }
      } else {
        if (!_disposed && mounted) {
          setState(() {
            _toggleLoading = false;
          });
        }
      }

      await _updateSummary(userDocRef);
    } catch (e) {}
  }

  Future<List<bool>> _getReadStatusForRange(int daysBack) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final userDocRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    final readingCollection = userDocRef.collection('reading');

    List<bool> statuses = [];

    for (int i = 0; i < daysBack; i++) {
      final date = DateTime.now().subtract(Duration(days: i));
      final key = '${date.year}-${date.month}-${date.day}';
      final doc = await readingCollection.doc(key).get();
      statuses.add(doc.exists && doc.data()?['read'] == true);
    }

    return statuses.reversed.toList();
  }

  Future<int> _calculateStreak() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    final userDocRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    final readingCollection = userDocRef.collection('reading');

    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 60));
    final snapshot = await readingCollection
        .where('read', isEqualTo: true)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .orderBy('timestamp', descending: true)
        .limit(60)
        .get();

    int streak = 0;
    DateTime expected = DateTime(now.year, now.month, now.day);
    for (final doc in snapshot.docs) {
      final ts = doc.data()['timestamp'];
      if (ts is! Timestamp) break;
      final date = ts.toDate();
      final normalized = DateTime(date.year, date.month, date.day);
      if (normalized == expected) {
        streak++;
        expected = expected.subtract(const Duration(days: 1));
      } else if (normalized.isBefore(expected)) {
        break;
      }
    }
    return streak;
  }

  Future<void> _updateSummary(DocumentReference userDocRef) async {
    final streak = await _calculateStreak();
    final pastWeekStatus = await _getReadStatusForRange(7);
    final pastMonthStatus = await _getReadStatusForRange(30);

    final pastWeekReadDays = <int>[];
    for (int i = 0; i < pastWeekStatus.length; i++) {
      final day = DateTime.now()
          .subtract(Duration(days: pastWeekStatus.length - 1 - i));
      if (pastWeekStatus[i]) pastWeekReadDays.add(day.weekday);
    }

    final pastMonthReadDays = <int>[];
    for (int i = 0; i < pastMonthStatus.length; i++) {
      final day = DateTime.now()
          .subtract(Duration(days: pastMonthStatus.length - 1 - i));
      if (pastMonthStatus[i]) pastMonthReadDays.add(day.day);
    }

    await userDocRef.collection('summary').doc('data').set({
      'streak': streak,
      'pastWeekReadDays': pastWeekReadDays,
      'pastMonthReadDays': pastMonthReadDays,
    }, SetOptions(merge: true));

    if (!_disposed && mounted) {
      setState(() {
        _streak = streak;
        _pastWeek = pastWeekStatus;
        _pastMonth = pastMonthStatus;
      });
    }
  }

  Future<void> _toggleReadStatus() async {
    if (_readToday) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!_disposed && mounted) {
      setState(() {
        _readToday = true;
      });
    }

    final today = DateTime.now();
    final dateKey = '${today.year}-${today.month}-${today.day}';

    await FirebaseFirestore.instance
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc(user.uid)
        .set({
      'name': user.displayName ?? '',
      'email': user.email ?? '',
      'timestamp': Timestamp.now(),
      'read': true,
    });

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('reading')
        .doc(dateKey)
        .set({'read': true, 'timestamp': Timestamp.now()},
            SetOptions(merge: true));

    final userDocRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    await _updateSummary(userDocRef);
  }

  Future<void> likeReading() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final today = DateTime.now();
    final dateKey = '${today.year}-${today.month}-${today.day}';
    final userDocRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);

    await userDocRef
        .collection('reading')
        .doc(dateKey)
        .collection('likes')
        .doc(user.uid)
        .set({'timestamp': Timestamp.now()});
  }

  Future<void> unlikeReading() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final today = DateTime.now();
    final dateKey = '${today.year}-${today.month}-${today.day}';
    final userDocRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);

    await userDocRef
        .collection('reading')
        .doc(dateKey)
        .collection('likes')
        .doc(user.uid)
        .delete();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_loadedOnce) {
      _loadedOnce = true;
      _loadReadStatus();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bible Reading Challenge',
            style: CommonStyles.appBarTitleText),
        backgroundColor: Theme.of(context).colorScheme.primary,
        shape: CommonStyles.roundedAppBar,
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: _buildMainContent(),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return RefreshIndicator(
      onRefresh: () async {
        try {
          await _loadReadStatus();
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Refreshed successfully')));
        } catch (e) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 24, bottom: 48),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CommonStyles.buildCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.local_fire_department,
                        color: Colors.orange),
                    const SizedBox(width: 8),
                    Text(
                      "Streak: $_streak day${_streak == 1 ? '' : 's'}",
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CommonStyles.buildCard(
                child: _toggleLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : SwitchListTile(
                        value: _readToday,
                        onChanged:
                            _readToday ? null : (value) => _toggleReadStatus(),
                        title: const Text("Bible Read Today"),
                        activeColor: Colors.green,
                      ),
              ),
              const SizedBox(height: 16),
              CommonStyles.buildCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Builder(
                      builder: (context) {
                        final weekData = _pastWeek.length == 7
                            ? _pastWeek
                            : List<bool>.generate(
                                7,
                                (i) => i < _pastWeek.length
                                    ? _pastWeek[i]
                                    : false);
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(7, (i) {
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(
                                weekData[i]
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: weekData[i] ? Colors.green : Colors.grey,
                                size: 20,
                              ),
                            );
                          }),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text("This Week", style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CommonStyles.buildCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "${DateTime.now().year} – ${_monthName(DateTime.now().month)}",
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    Table(
                      defaultColumnWidth: const FixedColumnWidth(32),
                      children: [
                        TableRow(
                          children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                              .map((d) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    child: Center(
                                        child: Text(d,
                                            style:
                                                const TextStyle(fontSize: 10))),
                                  ))
                              .toList(),
                        ),
                        ..._buildMonthCalendar(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text("This Month", style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<TableRow> _buildMonthCalendar() {
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final totalDays = DateTime(now.year, now.month + 1, 0).day;
    final weekdayOffset = (firstDay.weekday - 1) % 7;

    final rows = <TableRow>[];
    List<Widget> currentRow = List.filled(7, const SizedBox.shrink());

    for (int i = 0; i < weekdayOffset; i++) {
      currentRow[i] = const SizedBox.shrink();
    }

    for (int day = 1; day <= totalDays; day++) {
      int index = weekdayOffset + day - 1;
      int weekRow = index ~/ 7;
      int weekdayIndex = index % 7;

      if (rows.length <= weekRow) {
        rows.add(TableRow(children: List.filled(7, const SizedBox.shrink())));
      }

      final filled = _pastMonth.length >= day && _pastMonth[day - 1];
      rows[weekRow].children[weekdayIndex] = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Icon(
            filled ? Icons.circle : Icons.circle_outlined,
            size: 12,
            color: filled ? Colors.green : Colors.grey,
          ),
        ),
      );
    }

    return rows;
  }

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
      'December'
    ];
    return months[month - 1];
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;
}

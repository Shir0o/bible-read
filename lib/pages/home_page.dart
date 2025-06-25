import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/common_styles.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _readToday = false;
  bool _loading = true;
  int _streak = 0;
  List<bool> _pastWeek = [];
  List<bool> _pastMonth = [];

  @override
  void initState() {
    super.initState();
    _loadReadStatus();
  }

  Future<void> _loadReadStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final today = DateTime.now();
    final dateKey = '${today.year}-${today.month}-${today.day}';

    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final userDoc = await userDocRef.get();
    if (!userDoc.exists) {
      await userDocRef.set({
        'name': user.displayName ?? '',
        'email': user.email ?? '',
      });

      final friendsCollection = userDocRef.collection('friends');
      final friendRequestsSentCollection = userDocRef.collection('friendRequestsSent');

      // These can be created later when adding/accepting friends,
      // but you can prepopulate with empty docs or placeholders if needed:
      // Example: initialize placeholder if needed
      await friendsCollection.doc('init').set({'status': 'placeholder', 'timestamp': Timestamp.now()}, SetOptions(merge: true));
      await friendRequestsSentCollection.doc('init').set({'status': 'placeholder', 'timestamp': Timestamp.now()}, SetOptions(merge: true));
    }

    final doc = await userDocRef
        .collection('reading')
        .doc(dateKey)
        .get();

    if (doc.exists && doc.data() != null) {
      setState(() {
        _readToday = doc['read'] ?? false;
      });
    }

    final summaryDoc = await userDocRef.collection('summary').doc('data').get();
    final data = summaryDoc.data() ?? {};
    int streak = data['streak'] ?? 0;

    final savedWeek = <bool>[];
    final savedWeekIndices = List<int>.from(data['pastWeekReadDays'] ?? []);
    for (int i = 0; i < 7; i++) {
      savedWeek.add(savedWeekIndices.contains(i + 1));
    }

    final savedMonth = <bool>[];
    final savedMonthIndices = List<int>.from(data['pastMonthReadDays'] ?? []);
    for (int i = 0; i < 30; i++) {
      savedMonth.add(savedMonthIndices.contains(i + 1));
    }

    if (savedWeekIndices.isEmpty) {
      final weekStatus = await _getReadStatusForRange(7);
      savedWeek.clear();
      savedWeek.addAll(weekStatus);
    }
    if (savedMonthIndices.isEmpty) {
      final monthStatus = await _getReadStatusForRange(30);
      savedMonth.clear();
      savedMonth.addAll(monthStatus);
    }

    setState(() {
      _streak = streak;
      _loading = false;
      _pastWeek = savedWeek;
      _pastMonth = savedMonth;
    });
  }

  Future<List<bool>> _getReadStatusForRange(int daysBack) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
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

  Future<void> _toggleReadStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final today = DateTime.now();
    final dateKey = '${today.year}-${today.month}-${today.day}';
    final newStatus = !_readToday;

    await FirebaseFirestore.instance
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc(user.uid)
        .set({
          'name': user.displayName ?? '',
          'email': user.email ?? '',
          'timestamp': Timestamp.now(),
          'read': newStatus,
        });

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('reading')
        .doc(dateKey)
        .set({'read': newStatus}, SetOptions(merge: true));

    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final readingCollection = userDocRef.collection('reading');

    // Update streak
    int streak = newStatus ? (_readToday ? _streak : _streak + 1) : (_streak > 0 ? _streak - 1 : 0);

    // Update day index for today
    final now = DateTime.now();
    int todayIndexWeek = now.weekday; // 1 (Mon) to 7 (Sun)
    int todayIndexMonth = now.day; // 1–31

    // Build index lists with only today's update
    final pastWeekReadDays = newStatus ? [todayIndexWeek] : [];
    final pastMonthReadDays = newStatus ? [todayIndexMonth] : [];

    await userDocRef.collection('summary').doc('data').set({
      'streak': streak,
      'pastWeekReadDays': pastWeekReadDays,
      'pastMonthReadDays': pastMonthReadDays,
    }, SetOptions(merge: true));

    setState(() {
      _readToday = newStatus;
      _streak = streak;
      _pastWeek = List.generate(7, (i) => i + 1 == todayIndexWeek ? newStatus : false);
      _pastMonth = List.generate(30, (i) => i + 1 == todayIndexMonth ? newStatus : false);
    });
  }

  Future<void> likeReading() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final today = DateTime.now();
    final dateKey = '${today.year}-${today.month}-${today.day}';
    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

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
    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    await userDocRef
        .collection('reading')
        .doc(dateKey)
        .collection('likes')
        .doc(user.uid)
        .delete();
  }

  Future<void> _syncSummaryForUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final readingCollection = userDocRef.collection('reading');

    // Recalculate streak
    int streak = 0;
    DateTime currentDate = DateTime.now();
    while (true) {
      final key = '${currentDate.year}-${currentDate.month}-${currentDate.day}';
      final doc = await readingCollection.doc(key).get();
      if (doc.exists && doc.data()?['read'] == true) {
        streak++;
        currentDate = currentDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }

    final pastWeekStatus = await _getReadStatusForRange(7);
    final pastMonthStatus = await _getReadStatusForRange(30);

    final pastWeekReadDays = <int>[];
    for (int i = 0; i < pastWeekStatus.length; i++) {
      if (pastWeekStatus[i]) pastWeekReadDays.add(i + 1);
    }

    final pastMonthReadDays = <int>[];
    for (int i = 0; i < pastMonthStatus.length; i++) {
      if (pastMonthStatus[i]) pastMonthReadDays.add(i + 1);
    }

    await userDocRef.collection('summary').doc('data').set({
      'streak': streak,
      'pastWeekReadDays': pastWeekReadDays,
      'pastMonthReadDays': pastMonthReadDays,
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bible Reading Challenge', style: CommonStyles.appBarTitleText),
        backgroundColor: Theme.of(context).colorScheme.primary,
        shape: CommonStyles.roundedAppBar,
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CommonStyles.buildCard(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.local_fire_department, color: Colors.orange),
                          SizedBox(width: 8),
                          Text(
                            "Streak: $_streak day${_streak == 1 ? '' : 's'}",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    CommonStyles.buildCard(
                      child: SwitchListTile(
                        value: _readToday,
                        onChanged: (value) => _toggleReadStatus(),
                        title: const Text("Bible Read Today"),
                        activeColor: Colors.green,
                      ),
                    ),
                    SizedBox(height: 16),
                    CommonStyles.buildCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(_pastWeek.length, (i) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Icon(
                                  _pastWeek[i] ? Icons.check_circle : Icons.radio_button_unchecked,
                                  color: _pastWeek[i] ? Colors.green : Colors.grey,
                                  size: 20,
                                ),
                              );
                            }),
                          ),
                          SizedBox(height: 8),
                          Text("This Week", style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    CommonStyles.buildCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "${DateTime.now().year} – ${_monthName(DateTime.now().month)}",
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          Table(
                            defaultColumnWidth: FixedColumnWidth(24),
                            children: [
                              TableRow(
                                children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                                    .map((d) => Center(child: Text(d, style: TextStyle(fontSize: 10))))
                                    .toList(),
                              ),
                              ..._buildMonthCalendar(),
                            ],
                          ),
                          SizedBox(height: 4),
                          Text("This Month", style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _syncSummaryForUser,
        child: Icon(Icons.sync),
        tooltip: 'Sync Summary',
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

      rows[weekRow].children[weekdayIndex] = Center(
        child: Icon(
          _pastMonth.length >= day && _pastMonth[day - 1]
              ? Icons.circle
              : Icons.circle_outlined,
          size: 10,
          color: _pastMonth.length >= day && _pastMonth[day - 1]
              ? Colors.green
              : Colors.grey,
        ),
      );
    }

    return rows;
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }
}
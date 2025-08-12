import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/common_styles.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';

class HistoricalStreaksPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  HistoricalStreaksPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance;

  @override
  State<HistoricalStreaksPage> createState() => _HistoricalStreaksPageState();
}

class _HistoricalStreaksPageState extends State<HistoricalStreaksPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<dynamic>> _events = {};

  // For dropdowns
  late int _selectedYear;
  late int _selectedMonth;
  final List<int> _years =
      List<int>.generate(10, (i) => DateTime.now().year - i);
  final List<String> _months = DateFormat.MMMM().dateSymbols.MONTHS;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _selectedYear = _focusedDay.year;
    _selectedMonth = _focusedDay.month;
    _fetchReadDataForMonth(_focusedDay);
  }

  Future<void> _fetchReadDataForMonth(DateTime month) async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    final startOfMonth = DateTime(month.year, month.month, 1);
    final endOfMonth = DateTime(month.year, month.month + 1, 0);

    final readingCollection = widget.firestore
        .collection('users')
        .doc(user.uid)
        .collection('reading');

    final startKey =
        '${startOfMonth.year}-${startOfMonth.month.toString().padLeft(2, '0')}-${startOfMonth.day.toString().padLeft(2, '0')}';
    final endKey =
        '${endOfMonth.year}-${endOfMonth.month.toString().padLeft(2, '0')}-${endOfMonth.day.toString().padLeft(2, '0')}';

    final querySnapshot = await readingCollection
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: startKey)
        .where(FieldPath.documentId, isLessThanOrEqualTo: endKey)
        .get();

    final readDocs =
        querySnapshot.docs.where((doc) => doc.data()['read'] == true);

    final events = <DateTime, List<dynamic>>{};
    for (final doc in readDocs) {
      final parts = doc.id.split('-');
      final date = DateTime.utc(
          int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      events[date] = ['read'];
    }

    if (mounted) {
      setState(() {
        _events = events;
      });
    }
  }

  List<dynamic> _getEventsForDay(DateTime day) {
    // TableCalendar uses UTC dates for keys.
    final dayUtc = DateTime.utc(day.year, day.month, day.day);
    return _events[dayUtc] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History', style: CommonStyles.appBarTitleText),
        backgroundColor: AppTheme.backgroundColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: Column(
          children: [
            _buildMonthYearSelector(),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TableCalendar(
                    firstDay: DateTime.utc(2010, 1, 1),
                    lastDay: DateTime.now().add(const Duration(days: 365)),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    eventLoader: _getEventsForDay,
                    onPageChanged: (focusedDay) {
                      if (mounted) {
                        setState(() {
                          _focusedDay = focusedDay;
                          _selectedYear = focusedDay.year;
                          _selectedMonth = focusedDay.month;
                        });
                      }
                      _fetchReadDataForMonth(focusedDay);
                    },
                    headerVisible: false, // We have our own header
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (context, day, focusedDay) {
                        final dayUtc =
                            DateTime.utc(day.year, day.month, day.day);
                        final hasRead = _events.containsKey(dayUtc);
                        return Center(
                          child: Container(
                            decoration: BoxDecoration(
                              color: hasRead
                                  ? Colors.green.withAlpha(128)
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            width: 36,
                            height: 36,
                            child: Center(
                              child: Text(
                                '${day.day}',
                                style: TextStyle(
                                    color: day.month == _focusedDay.month
                                        ? Colors.white
                                        : Colors.white54),
                              ),
                            ),
                          ),
                        );
                      },
                      todayBuilder: (context, day, focusedDay) {
                        final dayUtc =
                            DateTime.utc(day.year, day.month, day.day);
                        final hasRead = _events.containsKey(dayUtc);
                        return Center(
                          child: Container(
                            decoration: BoxDecoration(
                              color: hasRead
                                  ? Colors.green.withAlpha(128)
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: AppTheme.colorScheme.primary,
                                  width: 2),
                            ),
                            width: 36,
                            height: 36,
                            child: Center(
                              child: Text(
                                '${day.day}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        );
                      },
                      outsideBuilder: (context, day, focusedDay) {
                        return Center(
                          child: Text(
                            '${day.day}',
                            style: const TextStyle(color: Colors.white30),
                          ),
                        );
                      },
                    ),
                    calendarStyle: const CalendarStyle(
                      defaultTextStyle: TextStyle(color: Colors.white),
                      weekendTextStyle: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthYearSelector() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      color: AppTheme.backgroundColor.withAlpha(128),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DropdownButton<int>(
            value: _selectedMonth,
            dropdownColor: AppTheme.colorScheme.surface,
            style: const TextStyle(color: Colors.white),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
            onChanged: (int? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedMonth = newValue;
                  _focusedDay = DateTime(_selectedYear, _selectedMonth, 1);
                });
                _fetchReadDataForMonth(_focusedDay);
              }
            },
            items: List.generate(12, (index) {
              return DropdownMenuItem<int>(
                value: index + 1,
                child: Text(_months[index]),
              );
            }),
          ),
          const SizedBox(width: 20),
          DropdownButton<int>(
            value: _selectedYear,
            dropdownColor: AppTheme.colorScheme.surface,
            style: const TextStyle(color: Colors.white),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
            onChanged: (int? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedYear = newValue;
                  _focusedDay = DateTime(_selectedYear, _selectedMonth, 1);
                });
                _fetchReadDataForMonth(_focusedDay);
              }
            },
            items: _years.map<DropdownMenuItem<int>>((int value) {
              return DropdownMenuItem<int>(
                value: value,
                child: Text(value.toString()),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

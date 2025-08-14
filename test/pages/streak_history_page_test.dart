import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/streak_history_page.dart';

void main() {
  testWidgets('displays streak stats', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'));

    final now = DateTime.now();
    final week = <String>[];
    final month = <String>[];
    for (int i = 0; i < 3; i++) {
      final d = now.subtract(Duration(days: i));
      await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc('${d.year}-${d.month}-${d.day}')
          .set({'read': true});
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      week.add(key);
      month.add(key);
    }

    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({
      'streak': 3,
      'pastWeekReadDates': week,
      'pastMonthReadDates': month,
      'totalReadDays': 3,
      'longestStreak': 3,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: StreakHistoryPage(firestore: firestore, auth: auth),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Current streak: 3'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);
  });
}

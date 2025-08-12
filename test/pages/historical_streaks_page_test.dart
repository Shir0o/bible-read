import 'package:bible_read/pages/historical_streaks_page.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';

void main() {
  testWidgets('HistoricalStreaksPage renders', (WidgetTester tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1'));

    await firestore
        .collection('users')
        .doc('u1')
        .collection('reading')
        .doc('2024-01-01')
        .set({'read': true});

    await tester.pumpWidget(MaterialApp(
      home: HistoricalStreaksPage(
        firestore: firestore,
        auth: auth,
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.text('History'), findsOneWidget);
    expect(find.byType(TableCalendar), findsOneWidget);
  });
}

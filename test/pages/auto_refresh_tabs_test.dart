// ignore_for_file: subtype_of_sealed_class

import 'package:bible_read/pages/home_page.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Home shows a remote reading change without pull-to-refresh',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    final today = DateTime(2024, 7, 30);
    const dateKey = '2024-07-30';

    await firestore.collection('users').doc('u1').set({'name': 'U'});
    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({
      'pastWeekReadDates': [dateKey],
      'pastMonthReadDates': [dateKey],
      'streak': 1,
    });
    await firestore
        .collection('users')
        .doc('u1')
        .collection('reading')
        .doc(dateKey)
        .set({'read': true});

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          dateProvider: () => today,
          enableDriftAnimation: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('You read today \u2014 open check-in'),
      findsOneWidget,
    );

    await firestore
        .collection('users')
        .doc('u1')
        .collection('reading')
        .doc(dateKey)
        .set({'read': false});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.bySemanticsLabel('Open today\u2019s check-in'),
      findsOneWidget,
    );
  });
}

// ignore_for_file: subtype_of_sealed_class

import 'package:bible_read/pages/check_in_page.dart';
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

  testWidgets(
      'Home refreshes reading state and auto-opens check-in when resuming on a new day',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    var currentDate = DateTime(2024, 7, 30);
    const day1Key = '2024-07-30';

    await firestore.collection('users').doc('u1').set({'name': 'U'});
    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({
      'pastWeekReadDates': [day1Key],
      'pastMonthReadDates': [day1Key],
      'streak': 1,
    });
    // Day 1 was marked as read.
    await firestore
        .collection('users')
        .doc('u1')
        .collection('reading')
        .doc(day1Key)
        .set({'read': true});

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          dateProvider: () => currentDate,
          enableDriftAnimation: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Day 1 was read, so SunMark shows "You read today — open check-in"
    expect(
      find.bySemanticsLabel('You read today \u2014 open check-in'),
      findsOneWidget,
    );

    // App is backgrounded overnight, calendar advances to Day 2 (which has NOT been read).
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    currentDate = DateTime(2024, 7, 31);

    // App is resumed the next morning.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pumpAndSettle();

    // CheckInPage was auto-opened for the new day because Day 2 is unread!
    expect(find.byType(CheckInPage), findsOneWidget);
    expect(find.bySemanticsLabel('Dismiss check-in'), findsOneWidget);

    // Dismiss check-in to inspect HomePage header.
    await tester.tap(find.bySemanticsLabel('Dismiss check-in'));
    await tester.pumpAndSettle();

    // For Day 2 (unmarked), SunMark should NOT say "You read today", and check-in should be available
    expect(
      find.bySemanticsLabel('Open today\u2019s check-in'),
      findsOneWidget,
      reason:
          'SunMark should reflect unmarked status for the new day instead of remaining marked from yesterday',
    );

    // A pull-to-refresh refreshes the reading state but must not re-open the
    // check-in that was already auto-opened for the day (#1035 regression).
    await tester.fling(
        find.byType(CustomScrollView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(find.byType(CheckInPage), findsNothing);
    expect(find.text('I READ'), findsNothing);
  });

  testWidgets(
      'resuming on a new day does not stack a second check-in over an open one',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    var currentDate = DateTime(2024, 7, 30);

    await firestore.collection('users').doc('u1').set({'name': 'U'});

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          dateProvider: () => currentDate,
          enableDriftAnimation: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Day 1 is unread, so the check-in auto-opens and stays open.
    expect(
      find.byType(CheckInPage, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('I READ', skipOffstage: false), findsOneWidget);

    // App is backgrounded overnight and resumed with the check-in still open.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    currentDate = DateTime(2024, 7, 31);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(
      find.byType(CheckInPage, skipOffstage: false),
      findsOneWidget,
      reason: 'The new day must not push a second check-in over the open one',
    );
    expect(
      find.text('I READ', skipOffstage: false),
      findsOneWidget,
      reason: 'Only one check-in may be on the stack',
    );
  });
}

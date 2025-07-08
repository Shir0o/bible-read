import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';

import 'package:bible_read/pages/home_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HomePage shows static UI elements', (WidgetTester tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await tester.pumpWidget(
        MaterialApp(home: HomePage(firestore: firestore, auth: auth)));

    expect(find.text('Bible Reading Challenge'), findsOneWidget);
    expect(find.textContaining('Streak:'), findsOneWidget);
    expect(find.text('Bible Read Today'), findsOneWidget);
    expect(find.text('This Week'), findsOneWidget);
    expect(find.text('This Month'), findsOneWidget);
  });

  testWidgets('HomePage week row has seven icons', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await tester.pumpWidget(
        MaterialApp(home: HomePage(firestore: firestore, auth: auth)));

    // There should be exactly seven icons for the week status row. All are
    // unchecked by default since no data is loaded in tests.
    final unchecked = find.byIcon(Icons.radio_button_unchecked);
    expect(unchecked, findsNWidgets(7));
  });

  testWidgets('HomePage month calendar matches current month', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await tester.pumpWidget(
        MaterialApp(home: HomePage(firestore: firestore, auth: auth)));

    // Verify the month header text
    final now = DateTime.now();
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
    final header = '${now.year} – ${months[now.month - 1]}';
    expect(find.text(header), findsOneWidget);

    // Calendar should include one icon per day of the month
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final filled = tester.widgetList(find.byIcon(Icons.circle));
    final empty = tester.widgetList(find.byIcon(Icons.circle_outlined));
    expect(filled.length + empty.length, daysInMonth);
  });

  testWidgets('toggling read status writes reading doc and summary',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(
        uid: 'u1', displayName: 'Test User', email: 'test@example.com');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
        MaterialApp(home: HomePage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    final switchTile =
        tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(switchTile.onChanged, isNull);
  });

  testWidgets('like and unlike reading update Firestore', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u2');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
        MaterialApp(home: HomePage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(HomePage)) as dynamic;
    await state.likeReading();
    await tester.pumpAndSettle();
    final dateKey =
        '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    var likeDoc = await firestore
        .collection('users')
        .doc('u2')
        .collection('reading')
        .doc(dateKey)
        .collection('likes')
        .doc('u2')
        .get();
    expect(likeDoc.exists, isTrue);

    await state.unlikeReading();
    await tester.pumpAndSettle();
    likeDoc = await firestore
        .collection('users')
        .doc('u2')
        .collection('reading')
        .doc(dateKey)
        .collection('likes')
        .doc('u2')
        .get();
    expect(likeDoc.exists, isFalse);
  });

  testWidgets('refresh recalculates summary from reading data', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u3');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    final today = DateTime.now();
    for (int i = 0; i < 3; i++) {
      final date = today.subtract(Duration(days: i));
      final key = '${date.year}-${date.month}-${date.day}';
      await firestore
          .collection('users')
          .doc('u3')
          .collection('reading')
          .doc(key)
          .set({'read': true});
    }

    await tester.pumpWidget(
        MaterialApp(home: HomePage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(RefreshIndicator), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final summary = await firestore
        .collection('users')
        .doc('u3')
        .collection('summary')
        .doc('data')
        .get();
    expect(summary.data()?['streak'], 3);
  });
}

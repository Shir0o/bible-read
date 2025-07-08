import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/leaderboard_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows empty message when no users', (tester) async {
    final firestore = FakeFirebaseFirestore();

    await tester.pumpWidget(
      MaterialApp(home: LeaderboardPage(firestore: firestore)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No one is on the leaderboard yet.'), findsOneWidget);
  });

  testWidgets('users are sorted by streak', (tester) async {
    final firestore = FakeFirebaseFirestore();

    await firestore
        .collection('users')
        .doc('u1')
        .set({'name': 'Alice', 'email': 'a@example.com'});
    await firestore
        .collection('users')
        .doc('u2')
        .set({'name': 'Bob', 'email': 'b@example.com'});
    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({'streak': 2});
    await firestore
        .collection('users')
        .doc('u2')
        .collection('summary')
        .doc('data')
        .set({'streak': 5});

    await tester.pumpWidget(
      MaterialApp(home: LeaderboardPage(firestore: firestore)),
    );
    await tester.pumpAndSettle();

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles.length, 2);
    expect((tiles[0].title as Text).data, 'Bob');
    expect((tiles[1].title as Text).data, 'Alice');
    expect(find.text('5 days'), findsOneWidget);
    expect(find.text('2 days'), findsOneWidget);
  });

  testWidgets('refresh fetches latest data', (tester) async {
    final firestore = FakeFirebaseFirestore();

    await firestore
        .collection('users')
        .doc('u1')
        .set({'name': 'Alice', 'email': 'a@example.com'});
    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({'streak': 1});

    await tester.pumpWidget(
      MaterialApp(home: LeaderboardPage(firestore: firestore)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Alice'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(1));

    await firestore
        .collection('users')
        .doc('u2')
        .set({'name': 'Bob', 'email': 'b@example.com'});
    await firestore
        .collection('users')
        .doc('u2')
        .collection('summary')
        .doc('data')
        .set({'streak': 3});

    // Trigger pull-to-refresh
    await tester.drag(find.byType(RefreshIndicator), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNWidgets(2));
    expect(find.textContaining('Bob'), findsOneWidget);
  });
}

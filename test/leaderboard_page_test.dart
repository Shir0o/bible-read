import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bible_read/pages/leaderboard_page.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';

class _ErrorFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    throw Exception('fail');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('displays message when no data', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await tester.pumpWidget(
        MaterialApp(home: LeaderboardPage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();

    expect(find.text('No one is on the leaderboard yet.'), findsOneWidget);
  });

  testWidgets('shows sorted leaderboard', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('users').doc('u1').set({'name': 'Alice'});
    await firestore.collection('users').doc('u2').set({'name': 'Bob'});
    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({'streak': 1});
    await firestore
        .collection('users')
        .doc('u2')
        .collection('summary')
        .doc('data')
        .set({'streak': 5});

    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u2'), signedIn: true);
    await tester.pumpWidget(
        MaterialApp(home: LeaderboardPage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles.length, 2);
    expect((tiles[0].title as Text).data, 'Bob');
    expect((tiles[1].title as Text).data, 'Alice');
  });

  testWidgets('refresh reloads data', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('users').doc('u1').set({'name': 'Alice'});
    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({'streak': 1});

    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u3'), signedIn: true);
    await tester.pumpWidget(
        MaterialApp(home: LeaderboardPage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsOneWidget);

    await firestore.collection('users').doc('u2').set({'name': 'Bob'});
    await firestore
        .collection('users')
        .doc('u2')
        .collection('summary')
        .doc('data')
        .set({'streak': 2});

    await tester.drag(find.byType(RefreshIndicator), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNWidgets(2));
  });

  testWidgets('error shows snackbar', (tester) async {
    final firestore = _ErrorFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u4'), signedIn: true);
    await tester.pumpWidget(
        MaterialApp(home: LeaderboardPage(firestore: firestore, auth: auth)));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Error loading leaderboard'), findsOneWidget);
  });
}

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fake_cloud_firestore/src/mock_collection_reference.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bible_read/pages/leaderboard_page.dart';

class ThrowingUsersCollection
    extends MockCollectionReference<Map<String, dynamic>> {
  ThrowingUsersCollection(
    FakeFirebaseFirestore firestore,
    String path,
    Map<String, dynamic> root,
    Map<String, dynamic> docsData,
    Map<String, dynamic> snapshotStreamControllerRoot,
  ) : super(firestore, path, root, docsData, snapshotStreamControllerRoot);

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    throw FirebaseException(plugin: 'firestore');
  }
}

class ThrowingFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    final base =
        super.collection(path) as MockCollectionReference<Map<String, dynamic>>;
    if (path == 'users') {
      return ThrowingUsersCollection(
        this,
        base.path,
        base.root,
        base.docsData,
        base.snapshotStreamControllerRoot,
      );
    }
    return base;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('displays message when no data', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true);
    await tester.pumpWidget(
        MaterialApp(home: LeaderboardPage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();

    expect(find.text('No one is on the leaderboard yet.'), findsOneWidget);
  });

  testWidgets('shows sign in prompt when not authenticated', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: false);

    await tester.pumpWidget(
        MaterialApp(home: LeaderboardPage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();

    expect(
        find.text('Please sign in to view the leaderboard.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows sign in prompt when auth has no user', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth();

    await tester.pumpWidget(
        MaterialApp(home: LeaderboardPage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();

    expect(
        find.text('Please sign in to view the leaderboard.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows sorted leaderboard', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true);
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

    await tester.pumpWidget(
        MaterialApp(home: LeaderboardPage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles.length, 2);
    expect((tiles[0].title as Text).data, 'Bob');
    expect((tiles[1].title as Text).data, 'Alice');
  });

  testWidgets('failure hides loading indicator', (tester) async {
    final firestore = ThrowingFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await tester.pumpWidget(
        MaterialApp(home: LeaderboardPage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

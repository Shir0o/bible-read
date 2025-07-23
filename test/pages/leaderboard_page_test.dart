// ignore_for_file: subtype_of_sealed_class

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fake_cloud_firestore/src/mock_collection_reference.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bible_read/services/friend_service.dart';

import 'package:bible_read/pages/leaderboard_page.dart';

class ThrowingUsersCollection
    extends MockCollectionReference<Map<String, dynamic>> {
  ThrowingUsersCollection(
    super.firestore,
    super.path,
    super.root,
    super.docsData,
    super.snapshotStreamControllerRoot,
  );

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
    await tester.pumpWidget(MaterialApp(
        home: LeaderboardPage(
      firestore: firestore,
      auth: auth,
      friendService: FriendService(firestore: firestore),
    )));
    await tester.pumpAndSettle();

    expect(find.text('No one is on the leaderboard yet.'), findsOneWidget);
  });

  testWidgets('shows sign in prompt when not authenticated', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: false);

    await tester.pumpWidget(MaterialApp(
        home: LeaderboardPage(
      firestore: firestore,
      auth: auth,
      friendService: FriendService(firestore: firestore),
    )));
    await tester.pumpAndSettle();

    expect(
        find.text('Please sign in to view the leaderboard.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows sign in prompt when auth has no user', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth();

    await tester.pumpWidget(MaterialApp(
        home: LeaderboardPage(
      firestore: firestore,
      auth: auth,
      friendService: FriendService(firestore: firestore),
    )));
    await tester.pumpAndSettle();

    expect(
        find.text('Please sign in to view the leaderboard.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('tabs are present', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true);
    await tester.pumpWidget(MaterialApp(
        home: LeaderboardPage(
      firestore: firestore,
      auth: auth,
      friendService: FriendService(firestore: firestore),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Public'), findsOneWidget);
    expect(find.text('Friends'), findsOneWidget);
  });

  testWidgets('public tab shows sorted leaderboard', (tester) async {
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

    await tester.pumpWidget(MaterialApp(
        home: LeaderboardPage(
      firestore: firestore,
      auth: auth,
      friendService: FriendService(firestore: firestore),
    )));
    await tester.pumpAndSettle();

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles.length, 2);
    expect((tiles[0].title as Text).data, 'Bob');
    expect((tiles[1].title as Text).data, 'Alice');
  });

  testWidgets('friends tab shows only friend entries', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'me'), signedIn: true);
    await firestore.collection('users').doc('me').set({'name': 'Me'});
    await firestore.collection('users').doc('f1').set({'name': 'Friend'});
    await firestore.collection('users').doc('u2').set({'name': 'Other'});

    await firestore
        .collection('users')
        .doc('f1')
        .collection('summary')
        .doc('data')
        .set({'streak': 3});
    await firestore
        .collection('users')
        .doc('u2')
        .collection('summary')
        .doc('data')
        .set({'streak': 5});

    await firestore
        .collection('users')
        .doc('me')
        .collection('friends')
        .doc('f1')
        .set({'name': 'Friend'});

    await tester.pumpWidget(MaterialApp(
        home: LeaderboardPage(
      firestore: firestore,
      auth: auth,
      friendService: FriendService(firestore: firestore),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles.length, 2);
    expect((tiles[0].title as Text).data, 'Friend');
    expect((tiles[1].title as Text).data, 'Me');
  });

  testWidgets('friends tab includes user entry sorted by streak',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'me'), signedIn: true);
    await firestore.collection('users').doc('me').set({'name': 'Me'});
    await firestore.collection('users').doc('f1').set({'name': 'Friend'});

    await firestore
        .collection('users')
        .doc('me')
        .collection('summary')
        .doc('data')
        .set({'streak': 4});
    await firestore
        .collection('users')
        .doc('f1')
        .collection('summary')
        .doc('data')
        .set({'streak': 6});

    await firestore
        .collection('users')
        .doc('me')
        .collection('friends')
        .doc('f1')
        .set({'name': 'Friend'});

    await tester.pumpWidget(MaterialApp(
        home: LeaderboardPage(
      firestore: firestore,
      auth: auth,
      friendService: FriendService(firestore: firestore),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles.length, 2);
    expect((tiles[0].title as Text).data, 'Friend');
    expect((tiles[1].title as Text).data, 'Me');
  });

  testWidgets('failure hides loading indicator', (tester) async {
    final firestore = ThrowingFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await tester.pumpWidget(MaterialApp(
        home: LeaderboardPage(
      firestore: firestore,
      auth: auth,
      friendService: FriendService(firestore: firestore),
    )));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

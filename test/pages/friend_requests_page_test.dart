import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bible_read/models/friend_streak_link.dart';
import 'package:bible_read/pages/friend_requests_page.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late FriendService service;
  late MockFirebaseAuth auth;
  late bool acceptCalled;
  late bool deleteCalled;
  late Future<void> Function() seedFriendship;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    acceptCalled = false;
    deleteCalled = false;
    service = FriendService(
      firestore: firestore,
      notificationService: NotificationService(firestore: firestore),
      acceptFriendRequestFn: ({
        required String fromUid,
        required String toUid,
        required String fromName,
        required String toName,
      }) async {
        acceptCalled = true;
        await firestore
            .collection(FriendCollections.users)
            .doc(fromUid)
            .collection(FriendCollections.sentRequests)
            .doc(toUid)
            .delete();
        await firestore
            .collection(FriendCollections.users)
            .doc(toUid)
            .collection(FriendCollections.receivedRequests)
            .doc(fromUid)
            .delete();
        await firestore
            .collection(FriendCollections.users)
            .doc(fromUid)
            .collection(FriendCollections.friends)
            .doc(toUid)
            .set({'timestamp': Timestamp.now(), 'name': toName});
        await firestore
            .collection(FriendCollections.users)
            .doc(toUid)
            .collection(FriendCollections.friends)
            .doc(fromUid)
            .set({'timestamp': Timestamp.now(), 'name': fromName});
      },
      deleteFriendRequestPairFn: ({
        required String fromUid,
        required String toUid,
      }) async {
        deleteCalled = true;
        await firestore
            .collection(FriendCollections.users)
            .doc(fromUid)
            .collection(FriendCollections.sentRequests)
            .doc(toUid)
            .delete();
        await firestore
            .collection(FriendCollections.users)
            .doc(toUid)
            .collection(FriendCollections.receivedRequests)
            .doc(fromUid)
            .delete();
      },
    );
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'b', displayName: 'Bob'),
      signedIn: true,
    );

    seedFriendship = () async {
      await firestore
          .collection(FriendCollections.users)
          .doc('a')
          .collection(FriendCollections.friends)
          .doc('b')
          .set({'name': 'Bob'});
      await firestore
          .collection(FriendCollections.users)
          .doc('b')
          .collection(FriendCollections.friends)
          .doc('a')
          .set({'name': 'Alice'});
    };
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FriendRequestsPage(friendService: service, auth: auth),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows message when no pending requests', (tester) async {
    await pumpPage(tester);

    expect(find.text('No friend requests'), findsOneWidget);
  });

  testWidgets('shows back button in app bar', (tester) async {
    await pumpPage(tester);

    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('shows pending requests for signed in user', (tester) async {
    await service.sendFriendRequest(
      fromUid: 'a',
      fromName: 'Alice',
      toUid: 'b',
    );

    await pumpPage(tester);

    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('accepting request updates Firestore and removes it',
      (tester) async {
    await service.sendFriendRequest(
      fromUid: 'a',
      fromName: 'Alice',
      toUid: 'b',
    );

    await pumpPage(tester);

    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    final friendDocA = await firestore
        .collection(FriendCollections.users)
        .doc('a')
        .collection(FriendCollections.friends)
        .doc('b')
        .get();
    final friendDocB = await firestore
        .collection(FriendCollections.users)
        .doc('b')
        .collection(FriendCollections.friends)
        .doc('a')
        .get();
    final receivedDoc = await firestore
        .collection(FriendCollections.users)
        .doc('b')
        .collection(FriendCollections.receivedRequests)
        .doc('a')
        .get();
    final sentDoc = await firestore
        .collection(FriendCollections.users)
        .doc('a')
        .collection(FriendCollections.sentRequests)
        .doc('b')
        .get();

    expect(friendDocA.exists, isTrue);
    expect(friendDocB.exists, isTrue);
    expect(receivedDoc.exists, isFalse);
    expect(sentDoc.exists, isFalse);
    expect(find.text('Alice'), findsNothing);
    expect(acceptCalled, isTrue);
  });

  testWidgets('declining request removes it without adding friends',
      (tester) async {
    await service.sendFriendRequest(
      fromUid: 'a',
      fromName: 'Alice',
      toUid: 'b',
    );

    await pumpPage(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    final sentDoc = await firestore
        .collection(FriendCollections.users)
        .doc('a')
        .collection(FriendCollections.sentRequests)
        .doc('b')
        .get();
    final receivedDoc = await firestore
        .collection(FriendCollections.users)
        .doc('b')
        .collection(FriendCollections.receivedRequests)
        .doc('a')
        .get();
    final friendDocA = await firestore
        .collection(FriendCollections.users)
        .doc('a')
        .collection(FriendCollections.friends)
        .doc('b')
        .get();

    expect(sentDoc.exists, isFalse);
    expect(receivedDoc.exists, isFalse);
    expect(friendDocA.exists, isFalse);
    expect(find.text('Alice'), findsNothing);
    expect(deleteCalled, isTrue);
  });

  testWidgets('shows streak invites section with actionable items',
      (tester) async {
    await seedFriendship();
    await service.sendStreakInvite(
      fromUid: 'a',
      fromName: 'Alice',
      toUid: 'b',
      toName: 'Bob',
    );

    await pumpPage(tester);

    expect(find.text('Streak invites'), findsOneWidget);
    expect(find.text('Alice'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Accept'), findsOneWidget);
  });

  testWidgets('accepting streak invite updates Firestore', (tester) async {
    await seedFriendship();
    await service.sendStreakInvite(
      fromUid: 'a',
      fromName: 'Alice',
      toUid: 'b',
      toName: 'Bob',
    );

    await pumpPage(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
    await tester.pumpAndSettle();

    final linkDoc = await firestore
        .collection(FriendCollections.users)
        .doc('b')
        .collection(FriendCollections.friendStreakLinks)
        .doc('a')
        .get();
    expect(linkDoc.exists, isTrue);
    expect(linkDoc.data()?['status'], FriendStreakStatus.active.name);
  });
}

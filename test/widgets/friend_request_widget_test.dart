import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:bible_read/widgets/friend_request_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late FriendService service;
  late bool acceptCalled;
  late bool deleteCalled;

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
  });

  Future<void> pumpRequestWidget(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FriendRequestWidget(
            service: service,
            currentUid: 'b',
            currentName: 'Bob',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('request appears after sending', (tester) async {
    await service.sendFriendRequest(
      fromUid: 'a',
      fromName: 'Alice',
      toUid: 'b',
    );

    await pumpRequestWidget(tester);

    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('accepting request adds friend and removes request',
      (tester) async {
    await service.sendFriendRequest(
      fromUid: 'a',
      fromName: 'Alice',
      toUid: 'b',
    );

    await pumpRequestWidget(tester);

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

    await pumpRequestWidget(tester);

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
}

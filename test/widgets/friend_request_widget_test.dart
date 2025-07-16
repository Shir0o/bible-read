import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/widgets/friend_request_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late FriendService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = FriendService(firestore: firestore);
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
    final requestDoc = await firestore
        .collection(FriendCollections.users)
        .doc('b')
        .collection(FriendCollections.receivedRequests)
        .doc('a')
        .get();

    expect(friendDocA.exists, isTrue);
    expect(friendDocB.exists, isTrue);
    expect(requestDoc.exists, isFalse);
    expect(find.text('Alice'), findsNothing);
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
  });
}

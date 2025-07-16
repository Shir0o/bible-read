import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/widgets/friend_request_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('request appears after sending', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = FriendService(firestore: firestore);

    await service.sendFriendRequest(
      fromUid: 'a',
      fromName: 'Alice',
      toUid: 'b',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FriendRequestWidget(service: service, currentUid: 'b'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('accepting request adds friend and removes request',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = FriendService(firestore: firestore);

    await service.sendFriendRequest(
      fromUid: 'a',
      fromName: 'Alice',
      toUid: 'b',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FriendRequestWidget(service: service, currentUid: 'b'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    final friendDocA = await firestore
        .collection('users')
        .doc('a')
        .collection('friends')
        .doc('b')
        .get();
    final friendDocB = await firestore
        .collection('users')
        .doc('b')
        .collection('friends')
        .doc('a')
        .get();
    final requestDoc = await firestore
        .collection('users')
        .doc('b')
        .collection('friendRequestsReceived')
        .doc('a')
        .get();

    expect(friendDocA.exists, isTrue);
    expect(friendDocB.exists, isTrue);
    expect(requestDoc.exists, isFalse);
    expect(find.text('Alice'), findsNothing);
  });

  testWidgets('declining request removes it without adding friends',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = FriendService(firestore: firestore);

    await service.sendFriendRequest(
      fromUid: 'a',
      fromName: 'Alice',
      toUid: 'b',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FriendRequestWidget(service: service, currentUid: 'b'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    final sentDoc = await firestore
        .collection('users')
        .doc('a')
        .collection('friendRequestsSent')
        .doc('b')
        .get();
    final receivedDoc = await firestore
        .collection('users')
        .doc('b')
        .collection('friendRequestsReceived')
        .doc('a')
        .get();
    final friendDocA = await firestore
        .collection('users')
        .doc('a')
        .collection('friends')
        .doc('b')
        .get();

    expect(sentDoc.exists, isFalse);
    expect(receivedDoc.exists, isFalse);
    expect(friendDocA.exists, isFalse);
    expect(find.text('Alice'), findsNothing);
  });
}

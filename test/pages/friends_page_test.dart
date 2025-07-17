import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bible_read/pages/friends_page.dart';
import 'package:bible_read/services/friend_service.dart';

class RecordingFriendService extends FriendService {
  RecordingFriendService({required FakeFirebaseFirestore firestore})
      : super(firestore: firestore);

  String? lastEmail;

  @override
  Future<void> sendFriendRequestByEmail({
    required String fromUid,
    required String fromName,
    required String toEmail,
  }) async {
    lastEmail = toEmail;
  }
}

class FailingFriendService extends FriendService {
  FailingFriendService({required FakeFirebaseFirestore firestore})
      : super(firestore: firestore);

  @override
  Future<void> sendFriendRequestByEmail({
    required String fromUid,
    required String fromName,
    required String toEmail,
  }) async {
    throw FirebaseException(plugin: 'firestore');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebaseFirestore firestore;
  late RecordingFriendService service;
  late MockFirebaseAuth auth;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = RecordingFriendService(firestore: firestore);
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1', displayName: 'Test User'),
      signedIn: true,
    );
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: FriendsPage(friendService: service, auth: auth)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('fab opens dialog and sends request', (tester) async {
    await pumpPage(tester);

    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'friend@example.com');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(service.lastEmail, 'friend@example.com');
  });

  testWidgets('friend list renders entries from service', (tester) async {
    await firestore
        .collection('users')
        .doc('u1')
        .collection('friends')
        .doc('f1')
        .set({'name': 'Alice'});

    await pumpPage(tester);

    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('failed request leaves send button enabled', (tester) async {
    final failing = FailingFriendService(firestore: firestore);
    await tester.pumpWidget(
      MaterialApp(home: FriendsPage(friendService: failing, auth: auth)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'x@example.com');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Send'));
    expect(button.onPressed, isNotNull);
  });
}

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/add_friend_page.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/notification_service.dart';

class RecordingFriendService extends FriendService {
  RecordingFriendService({required FakeFirebaseFirestore firestore})
      : super(
          firestore: firestore,
          notificationService: NotificationService(firestore: firestore),
        );

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebaseFirestore firestore;
  late RecordingFriendService service;
  late MockFirebaseAuth auth;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = RecordingFriendService(firestore: firestore);
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1', displayName: 'Tester'),
      signedIn: true,
    );
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AddFriendPage(friendService: service, auth: auth)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sends request with entered email', (tester) async {
    await pumpPage(tester);

    await tester.enterText(
        find.byKey(const Key('addFriendEmailField')), 'friend@example.com');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(service.lastEmail, 'friend@example.com');
  });
}

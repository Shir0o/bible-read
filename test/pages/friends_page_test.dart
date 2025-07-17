import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/friends_page.dart';
import 'package:bible_read/services/friend_service.dart';

class RecordingFriendService extends FriendService {
  RecordingFriendService() : super(firestore: FakeFirebaseFirestore());

  String? lastEmail;

  @override
  Future<void> sendFriendRequestByEmail({
    required String fromUid,
    required String fromName,
    required String toEmail,
  }) async {
    lastEmail = toEmail;
  }

  @override
  Stream<List<Friend>> friends(String uid) => Stream.value([]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fab opens dialog and sends request', (tester) async {
    final service = RecordingFriendService();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1', displayName: 'Test User'),
      signedIn: true,
    );

    await tester.pumpWidget(
      MaterialApp(home: FriendsPage(friendService: service, auth: auth)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'friend@example.com');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(service.lastEmail, 'friend@example.com');
    expect(find.text('Request sent'), findsOneWidget);
  });
}

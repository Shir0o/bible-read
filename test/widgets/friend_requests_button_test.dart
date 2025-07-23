import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/friend_requests_button.dart';
import 'package:bible_read/services/friend_service.dart';

class FakeFriendService extends FriendService {
  FakeFriendService({required this.stream})
      : super(firestore: FakeFirebaseFirestore());
  final Stream<List<FriendRequest>> stream;
  @override
  Stream<List<FriendRequest>> pendingRequests(String uid) => stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders new icon and tooltip', (tester) async {
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    final service = FakeFriendService(stream: Stream.value([]));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [
            FriendRequestsButton(friendService: service, auth: auth),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.person_add_alt_1), findsOneWidget);
    expect(find.byTooltip('Friend Requests'), findsOneWidget);
  });
}

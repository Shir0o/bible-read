import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

import 'package:bible_read/pages/friend_requests_page.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/widgets/friend_request_widget.dart';

import '../helpers/mock_lottie_http_client.dart';

class _StubVibrationService extends VibrationService {
  @override
  Future<void> lightImpact() async {}
}

class _StubFriendService extends FriendService {
  _StubFriendService() : super(firestore: FakeFirebaseFirestore());

  @override
  Stream<List<FriendRequest>> pendingRequests(String uid) {
    return Stream.value([]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
    setupLottieHttpOverrides();
  });
  tearDownAll(resetHttpOverrides);

  testWidgets('renders friend requests page', (tester) async {
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FriendRequestsPage(
          friendService: _StubFriendService(),
          auth: auth,
          vibrationService: _StubVibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Friend Requests'), findsOneWidget);
    expect(find.byType(FriendRequestWidget), findsOneWidget);
    // Should NOT find streak related text
    expect(find.text('Streak invites'), findsNothing);
  });
}

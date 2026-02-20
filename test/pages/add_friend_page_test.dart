// ignore_for_file: subtype_of_sealed_class

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

import 'package:bible_read/pages/add_friend_page.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/widgets/add_friend_form.dart';

import '../helpers/mock_lottie_http_client.dart';

class _StubVibrationService extends VibrationService {
  @override
  Future<void> mediumImpact() async {}
}

class _StubFriendService extends FriendService {
  _StubFriendService() : super(firestore: FakeFirebaseFirestore());

  @override
  Future<void> sendFriendRequestByEmail({
    required String fromUid,
    required String fromName,
    required String toEmail,
  }) async {
    // No-op
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

  testWidgets('renders add friend form', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AddFriendPage(
          friendService: _StubFriendService(),
          auth: auth,
          vibrationService: _StubVibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AddFriendForm), findsOneWidget);
    // Should NOT find streak related text
    expect(find.textContaining('Streak links:'), findsNothing);
  });
}

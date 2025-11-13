import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/add_friend_page.dart';
import 'package:bible_read/models/friend_streak_link.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:bible_read/services/vibration_service.dart';

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

class StubVibrationService extends VibrationService {
  const StubVibrationService();

  @override
  Future<void> lightImpact() async {}

  @override
  Future<void> mediumImpact() async {}

  @override
  Future<void> tap() async {}
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
      MaterialApp(
        home: AddFriendPage(
          friendService: service,
          auth: auth,
          vibrationService: const StubVibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sends request with entered email', (tester) async {
    await pumpPage(tester);

    await tester.enterText(
      find.byKey(const Key('addFriendEmailField')),
      'friend@example.com',
    );
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(service.lastEmail, 'friend@example.com');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('shows streak limit banner when max reached', (tester) async {
    for (var i = 0; i < FriendService.maxActiveStreakLinks; i++) {
      await firestore
          .collection(FriendCollections.users)
          .doc('u1')
          .collection(FriendCollections.friendStreakLinks)
          .doc('friend$i')
          .set({
        'partnerUid': 'friend$i',
        'partnerName': 'Friend $i',
        'initiatedBy': 'u1',
        'status': FriendStreakStatus.active.name,
        'currentStreak': 0,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });
    }

    await pumpPage(tester);

    expect(find.textContaining('Streak links:'), findsOneWidget);
    expect(
      find.textContaining('limit of streak partners'),
      findsOneWidget,
    );
  });
}

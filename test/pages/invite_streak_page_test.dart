import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bible_read/pages/invite_streak_page.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:bible_read/services/vibration_service.dart';

class _NoSemanticsBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get semanticsEnabled => false;
}

class RecordingFriendService extends FriendService {
  RecordingFriendService({required FakeFirebaseFirestore firestore})
      : super(
          firestore: firestore,
          notificationService: NotificationService(firestore: firestore),
        );

  String? lastEmail;
  bool nudged = false;

  @override
  Future<void> sendFriendRequestByEmail({
    required String fromUid,
    required String fromName,
    required String toEmail,
  }) async {
    lastEmail = toEmail;
  }

  @override
  Future<NudgeResult> nudgeFriend({
    required String currentUid,
    required String friendUid,
    required String currentName,
  }) async {
    nudged = true;
    return NudgeResult.sent;
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
  _NoSemanticsBinding();
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

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InviteStreakPage(
          friendService: service,
          auth: auth,
          vibrationService: const StubVibrationService(),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('streak invite button disabled when limit reached',
      (tester) async {
    await firestore
        .collection('users')
        .doc('u1')
        .collection('friends')
        .doc('f1')
        .set({'name': 'Alice'});
    for (var i = 0; i < FriendService.maxActiveStreakLinks; i++) {
      await firestore
          .collection('users')
          .doc('u1')
          .collection(FriendCollections.friendStreakLinks)
          .doc('friend$i')
          .set({
        'partnerUid': 'friend$i',
        'partnerName': 'Friend $i',
        'initiatedBy': 'u1',
        'status': 'active',
        'currentStreak': 1,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });
    }

    await pumpPage(tester);

    final buttonFinder = find.byKey(const Key('streakInviteButton_f1'));
    final button = tester.widget<FilledButton>(buttonFinder);
    expect(button.onPressed, isNull);
    expect(find.textContaining('Streak links:'), findsOneWidget);
  });

  testWidgets('shows pending label for outgoing streak invite', (tester) async {
    await firestore
        .collection('users')
        .doc('u1')
        .collection('friends')
        .doc('f1')
        .set({'name': 'Alice'});
    await firestore
        .collection('users')
        .doc('f1')
        .collection('friends')
        .doc('u1')
        .set({'name': 'Test User'});

    await service.sendStreakInvite(
      fromUid: 'u1',
      fromName: 'Test User',
      toUid: 'f1',
      toName: 'Alice',
    );

    await pumpPage(tester);

    expect(
      find.byKey(const Key('streakInvitePendingLabel_f1')),
      findsOneWidget,
    );
  });

  testWidgets('shows respond button for incoming streak invite',
      (tester) async {
    await firestore
        .collection('users')
        .doc('u1')
        .collection('friends')
        .doc('f1')
        .set({'name': 'Alice'});
    await firestore
        .collection('users')
        .doc('f1')
        .collection('friends')
        .doc('u1')
        .set({'name': 'Test User'});

    await service.sendStreakInvite(
      fromUid: 'f1',
      fromName: 'Alice',
      toUid: 'u1',
      toName: 'Test User',
    );

    await pumpPage(tester);

    expect(find.widgetWithText(FilledButton, 'Respond'), findsOneWidget);
  });
}

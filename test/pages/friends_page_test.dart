import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bible_read/pages/add_friend_page.dart';
import 'package:bible_read/pages/friends_page.dart';
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

class FailingFriendService extends FriendService {
  FailingFriendService({required FakeFirebaseFirestore firestore})
      : super(
          firestore: firestore,
          notificationService: NotificationService(firestore: firestore),
        );

  @override
  Future<void> sendFriendRequestByEmail({
    required String fromUid,
    required String fromName,
    required String toEmail,
  }) async {
    throw FirebaseException(plugin: 'firestore');
  }
}

class AlreadySentFriendService extends RecordingFriendService {
  AlreadySentFriendService({required super.firestore});

  @override
  Future<NudgeResult> nudgeFriend({
    required String currentUid,
    required String friendUid,
    required String currentName,
  }) async {
    nudged = true;
    return NudgeResult.alreadySent;
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
        home: FriendsPage(
          friendService: service,
          auth: auth,
          vibrationService: const StubVibrationService(),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('fab navigates to AddFriendPage', (tester) async {
    await pumpPage(tester);

    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);

    expect(find.byType(AddFriendPage), findsOneWidget);
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

  testWidgets('tapping nudge icon calls service', (tester) async {
    await firestore
        .collection('users')
        .doc('u1')
        .collection('friends')
        .doc('f1')
        .set({'name': 'Alice'});

    await pumpPage(tester);

    await tester.tap(find.byIcon(Icons.notifications_active));
    await settle(tester);

    expect(service.nudged, isTrue);
  });

  testWidgets('nudge button disabled after send', (tester) async {
    await firestore
        .collection('users')
        .doc('u1')
        .collection('friends')
        .doc('f1')
        .set({'name': 'Alice'});

    await pumpPage(tester);

    await tester.tap(find.byIcon(Icons.notifications_active));
    await settle(tester);

    final button = tester.widget<IconButton>(find.ancestor(
      of: find.byIcon(Icons.notifications_off),
      matching: find.byType(IconButton),
    ));
    expect(button.onPressed, isNull);
  });

  testWidgets('failed request leaves send button enabled', (tester) async {
    final failing = FailingFriendService(firestore: firestore);
    await tester.pumpWidget(
      MaterialApp(
        home: FriendsPage(
          friendService: failing,
          auth: auth,
          vibrationService: const StubVibrationService(),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(
        find.byKey(const Key('addFriendEmailField')), 'x@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await settle(tester);

    final button =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('already sent nudge disables button', (tester) async {
    final already = AlreadySentFriendService(firestore: firestore);
    await firestore
        .collection('users')
        .doc('u1')
        .collection('friends')
        .doc('f1')
        .set({'name': 'Alice'});

    await tester.pumpWidget(
      MaterialApp(
        home: FriendsPage(
          friendService: already,
          auth: auth,
          vibrationService: const StubVibrationService(),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.byIcon(Icons.notifications_active));
    await settle(tester);

    final button = tester.widget<IconButton>(find.ancestor(
      of: find.byIcon(Icons.notifications_off),
      matching: find.byType(IconButton),
    ));
    expect(button.onPressed, isNull);
  });

  testWidgets('existing nudge log disables nudge button', (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    await firestore
        .collection('users')
        .doc('u1')
        .collection('friends')
        .doc('f1')
        .set({'name': 'Alice'});

    await firestore
        .collection('users')
        .doc('u1')
        .collection('nudges')
        .doc('f1')
        .set({
      'timestamp': Timestamp.fromDate(start.add(const Duration(hours: 1)))
    });

    await pumpPage(tester);

    final button = tester.widget<IconButton>(find.ancestor(
      of: find.byIcon(Icons.notifications_off),
      matching: find.byType(IconButton),
    ));
    expect(button.onPressed, isNull);
  });
}

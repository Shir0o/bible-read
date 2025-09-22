import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bible_read/models/notification_preferences.dart';
import 'package:bible_read/models/app_notification.dart';
import 'package:bible_read/pages/notification_center_page.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:bible_read/pages/achievements_page.dart';
import 'package:bible_read/pages/friend_requests_page.dart';
import 'package:bible_read/pages/seasonal_challenges_page.dart';

Future<void> _renderType(WidgetTester tester, NotificationType type) async {
  final auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u0'), signedIn: true);
  final notification = AppNotification(
    id: 'id1',
    type: type,
    timestamp: DateTime.now(),
    read: false,
  );
  final service = _SingleNotificationService(notification: notification);
  await tester.pumpWidget(
    MaterialApp(
      home: NotificationCenterPage(service: service, auth: auth),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('maps notification types to icons and text', (tester) async {
    final iconMap = {
      NotificationType.like: Icons.thumb_up,
      NotificationType.nudge: Icons.notifications_active,
      NotificationType.signup: Icons.person_add,
      NotificationType.achievement: Icons.emoji_events,
      NotificationType.friendRequest: Icons.person_add_alt,
      NotificationType.comment: Icons.comment,
      NotificationType.groupJoinRequest: Icons.group_add,
      NotificationType.groupScheduleUpdate: Icons.schedule,
      NotificationType.seasonalChallenge: Icons.eco,
    };

    final textMap = {
      NotificationType.like: 'Someone liked your reading',
      NotificationType.nudge: 'You were nudged to read',
      NotificationType.signup: 'New signup',
      NotificationType.achievement: 'Achievement unlocked',
      NotificationType.friendRequest: 'You received a friend request',
      NotificationType.comment: 'New comment on your reading',
      NotificationType.groupJoinRequest: 'You received a group join request',
      NotificationType.groupScheduleUpdate: 'Group schedule updated',
      NotificationType.seasonalChallenge: 'Seasonal challenge reward ready',
    };

    for (final type in NotificationType.values) {
      await _renderType(tester, type);
      expect(find.byIcon(iconMap[type]!), findsOneWidget);
      expect(find.text(textMap[type]!), findsOneWidget);
    }
  });

  testWidgets('renders notifications from service', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = NotificationService(firestore: firestore);
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .doc('n1')
        .set({
      'type': NotificationType.like.name,
      'timestamp': Timestamp.now(),
      'read': false,
      'senderUid': 'u2',
      'message': 'Test like',
    });
    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .doc('n2')
        .set({
      'type': NotificationType.nudge.name,
      'timestamp': Timestamp.now(),
      'read': true,
      'senderUid': 'u3',
      'message': 'Test nudge',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationCenterPage(service: service, auth: auth),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test like'), findsOneWidget);
    expect(find.text('Test nudge'), findsOneWidget);
  });

  testWidgets('shows message when no notifications', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = NotificationService(firestore: firestore);
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u2'), signedIn: true);

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationCenterPage(service: service, auth: auth),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No notifications'), findsOneWidget);
  });

  testWidgets('shows loading indicator before notifications arrive',
      (tester) async {
    final controller = StreamController<List<AppNotification>>();
    addTearDown(controller.close);
    final service = _StreamNotificationsService(
      stream: controller.stream,
      firestore: FakeFirebaseFirestore(),
    );
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u5'), signedIn: true);

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationCenterPage(service: service, auth: auth),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('prompts sign in when user is not authenticated', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = _RecordingNotificationsService(firestore: firestore);
    final auth = MockFirebaseAuth(signedIn: false);

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationCenterPage(service: service, auth: auth),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Please sign in'), findsOneWidget);
    expect(service.subscribed, isFalse);
  });

  testWidgets('tapping achievement marks read and opens achievements',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = _RecordingService(firestore: firestore);
    final user = MockUser(uid: 'u3');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .doc('n1')
        .set({
      'type': NotificationType.achievement.name,
      'timestamp': Timestamp.now(),
      'read': false,
      'senderUid': 'u4',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationCenterPage(service: service, auth: auth),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();

    expect(service.called, isTrue);
    expect(service.uid, user.uid);
    expect(service.id, 'n1');
    expect(find.byType(AchievementsPage), findsOneWidget);
  });

  testWidgets('tapping friend request marks read and opens friend requests',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = _RecordingService(firestore: firestore);
    final user = MockUser(uid: 'u6');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .doc('n1')
        .set({
      'type': NotificationType.friendRequest.name,
      'timestamp': Timestamp.now(),
      'read': false,
      'senderUid': 'u7',
    });

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('friendRequestsReceived')
        .doc('u7')
        .set({'name': 'Alice'});

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationCenterPage(service: service, auth: auth),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();

    expect(service.called, isTrue);
    expect(service.uid, user.uid);
    expect(service.id, 'n1');
    expect(find.byType(FriendRequestsPage), findsOneWidget);
  });

  testWidgets('tapping seasonal challenge opens seasonal challenges',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = _RecordingService(firestore: firestore);
    final user = MockUser(uid: 'u10');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    final now = DateTime.now();
    await firestore.collection('seasons').doc('season').set({
      'title': 'Season',
      'description': 'Active season',
      'startDate': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
      'endDate': Timestamp.fromDate(now.add(const Duration(days: 10))),
    });
    await firestore
        .collection('seasons')
        .doc('season')
        .collection('challenges')
        .doc('challenge')
        .set({
      'seasonId': 'season',
      'title': 'Complete readings',
      'description': 'Finish readings',
      'metric': 'chapters',
      'goal': 1,
    });

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .doc('n1')
        .set({
      'type': NotificationType.seasonalChallenge.name,
      'timestamp': Timestamp.now(),
      'read': false,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationCenterPage(service: service, auth: auth),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();

    expect(find.byType(SeasonalChallengesPage), findsOneWidget);
  });

  testWidgets(
      'tapping friend request with no pending requests shows SnackBar and does not navigate',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = _RecordingService(firestore: firestore);
    final user = MockUser(uid: 'u8');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .doc('n1')
        .set({
      'type': NotificationType.friendRequest.name,
      'timestamp': Timestamp.now(),
      'read': false,
      'senderUid': 'u9',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationCenterPage(service: service, auth: auth),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ListTile));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('No pending friend requests'), findsOneWidget);
    expect(find.byType(FriendRequestsPage), findsNothing);
    expect(service.called, isTrue);
  });

  testWidgets(
      'shows SnackBar and keeps notification unread on markRead failure',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = _FailingService(firestore: firestore);
    final user = MockUser(uid: 'u4');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .doc('n1')
        .set({
      'type': NotificationType.like.name,
      'timestamp': Timestamp.now(),
      'read': false,
      'senderUid': 'u5',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationCenterPage(service: service, auth: auth),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ListTile));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Failed to mark notification as read.'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.thumb_up));
    expect(icon.color, Colors.blue);
  });
}

class _StreamNotificationsService extends NotificationService {
  _StreamNotificationsService({
    required this.stream,
    required super.firestore,
  });

  final Stream<List<AppNotification>> stream;

  @override
  Stream<List<AppNotification>> notifications(String uid) => stream;
}

class _RecordingNotificationsService extends NotificationService {
  _RecordingNotificationsService({required super.firestore});

  bool subscribed = false;

  @override
  Stream<List<AppNotification>> notifications(String uid) {
    subscribed = true;
    return const Stream.empty();
  }
}

class _RecordingService extends NotificationService {
  _RecordingService({required super.firestore});

  bool called = false;
  String? uid;
  String? id;

  @override
  Future<void> markRead(String uid, String notificationId) async {
    called = true;
    this.uid = uid;
    id = notificationId;
  }
}

class _FailingService extends NotificationService {
  _FailingService({required super.firestore});

  @override
  Future<void> markRead(String uid, String notificationId) async {
    throw Exception('markRead failed');
  }
}

class _SingleNotificationService extends NotificationService {
  _SingleNotificationService({required this.notification})
      : super(firestore: FakeFirebaseFirestore());

  final AppNotification notification;

  @override
  Stream<List<AppNotification>> notifications(String uid) =>
      Stream.value([notification]);
}

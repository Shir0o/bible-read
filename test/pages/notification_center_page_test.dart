import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bible_read/models/notification_preferences.dart';
import 'package:bible_read/pages/notification_center_page.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:bible_read/pages/achievements_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

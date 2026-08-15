import 'package:bible_read/models/app_notification.dart';
import 'package:bible_read/models/notification_preferences.dart';
import 'package:bible_read/pages/notification_center_page.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/services/notification_preferences_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FakeVibrationService implements VibrationService {
  @override
  FirebaseAuth? get auth => null;
  @override
  NotificationPreferencesService? get prefsService => null;

  @override
  Future<void> mediumImpact() async {}
  @override
  Future<void> lightImpact() async {}
  @override
  Future<void> heavyImpact() async {}
  @override
  Future<void> tap() async {}
}

void main() {
  group('NotificationCenterPage', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late NotificationService notificationService;
    late FakeVibrationService vibrationService;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(signedIn: true);
      notificationService = NotificationService(firestore: firestore);
      vibrationService = FakeVibrationService();
    });

    testWidgets('Renders empty state when no notifications', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationCenterPage(
            service: notificationService,
            auth: auth,
            vibrationService: vibrationService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('No notifications yet'), findsOneWidget);
      expect(find.text('Mark all read'), findsOneWidget);
    });

    testWidgets('Renders notifications as a flat card list', (tester) async {
      final uid = auth.currentUser!.uid;

      // Seed user2
      await firestore.collection('users').doc('user2').set({
        'name': 'User 2',
        'photoUrl': 'http://example.com/photo.jpg',
      });

      // Add a new notification
      await notificationService.addNotification(
        uid,
        AppNotification(
          id: '1',
          type: NotificationType.like,
          fromUid: 'user2',
          message: 'User 2 liked your reading',
          timestamp: DateTime.now(),
          read: false,
        ),
      );

      // Add an old read notification (Earlier this week)
      await notificationService.addNotification(
        uid,
        AppNotification(
          id: '2',
          type: NotificationType.comment,
          fromUid: 'user3',
          message: 'User 3 commented',
          timestamp: DateTime.now().subtract(const Duration(days: 2)),
          read: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationCenterPage(
            service: notificationService,
            auth: auth,
            vibrationService: vibrationService,
          ),
        ),
      );
      await tester.pumpAndSettle(); // Wait for stream

      // Use findRichText: true (default) but verifying separately to be safe with RichText splitting
      expect(
        find.text('User 2 liked your reading', findRichText: true),
        findsOneWidget,
      );
      // user3 not seeded, so name defaults to "Someone" but message is "User 3 commented".
      // _buildTextSpans checks if message starts with name. "User 3 commented".startsWith("Someone") is false.
      // So it renders raw message.
      expect(find.text('User 3 commented', findRichText: true), findsOneWidget);
    });

    testWidgets('Mark all as read calls service', (tester) async {
      final uid = auth.currentUser!.uid;

      await notificationService.addNotification(
        uid,
        AppNotification(
          id: '1',
          type: NotificationType.like,
          read: false,
          timestamp: DateTime.now(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationCenterPage(
            service: notificationService,
            auth: auth,
            vibrationService: vibrationService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();

      // Verify in firestore
      final doc = await firestore
          .collection(NotificationCollections.users)
          .doc(uid)
          .collection(NotificationCollections.notifications)
          .doc('1')
          .get();
      expect(doc.data()?['read'], isTrue);
    });
  });
}

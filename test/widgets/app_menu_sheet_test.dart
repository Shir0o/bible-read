import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/notification_preferences.dart';
import 'package:bible_read/models/app_notification.dart';
import 'package:bible_read/pages/admin/feedback_admin_page.dart';
import 'package:bible_read/pages/group_join_requests_page.dart';
import 'package:bible_read/pages/notification_center_page.dart';
import 'package:bible_read/pages/settings_page.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:bible_read/services/admin_role_service.dart';
import 'package:bible_read/services/feedback_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/widgets/app_menu_sheet.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

class _AlwaysAdminService extends AdminRoleService {
  _AlwaysAdminService()
      : super(auth: MockFirebaseAuth(), firestore: FakeFirebaseFirestore());

  @override
  Future<bool> isAdmin({bool allowStale = true}) async => true;
}

class _NeverAdminService extends AdminRoleService {
  _NeverAdminService()
      : super(auth: MockFirebaseAuth(), firestore: FakeFirebaseFirestore());

  @override
  Future<bool> isAdmin({bool allowStale = true}) async => false;
}

class _StaleCachedAdminService extends AdminRoleService {
  _StaleCachedAdminService(bool cachedValue)
      : super(auth: MockFirebaseAuth(), firestore: FakeFirebaseFirestore()) {
    primeCacheForTest(
      cachedValue,
      timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
    );
  }

  @override
  Future<bool> fetchAdminRole() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  Future<void> openSheet(
    WidgetTester tester, {
    AdminRoleService? admin,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    VibrationService? vibration,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AppMenuSheet.show(
                context: context,
                vibrationService: vibration ?? const VibrationService(),
                feedbackService: FeedbackService(
                  firestore: firestore ?? FakeFirebaseFirestore(),
                  auth: auth ?? MockFirebaseAuth(),
                ),
                adminRoleService: admin ?? _NeverAdminService(),
                auth: auth,
                firestore: firestore,
              ),
              child: const Text('Open menu'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();
  }

  Future<FakeFirebaseFirestore> seed(
    MockFirebaseAuth auth, {
    int unread = 0,
    int read = 0,
  }) async {
    final firestore = FakeFirebaseFirestore();
    final service = NotificationService(firestore: firestore);
    var minute = 0;
    for (var i = 0; i < unread; i++) {
      await service.addNotification(
        'u1',
        AppNotification(
          id: 'unread-$i',
          type: NotificationType.nudge,
          message: 'Unread message $i',
          timestamp: DateTime(2026, 1, 1, 8, minute++),
          read: false,
        ),
      );
    }
    for (var i = 0; i < read; i++) {
      await service.addNotification(
        'u1',
        AppNotification(
          id: 'read-$i',
          type: NotificationType.nudge,
          message: 'Read message $i',
          timestamp: DateTime(2026, 1, 1, 9, minute++),
          read: true,
        ),
      );
    }
    return firestore;
  }

  MockFirebaseAuth signedInAuth() => MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1', displayName: 'Test User'),
        signedIn: true,
      );

  testWidgets('shows profile, Settings, and no retired destinations', (
    tester,
  ) async {
    final auth = signedInAuth();
    final firestore = await seed(auth);
    await openSheet(tester, auth: auth, firestore: firestore);

    expect(find.text('Test User'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    for (final gone in [
      'Challenges',
      'Library',
      'Feedback',
      'History',
      'Sign out',
      'Inbox',
    ]) {
      expect(find.text(gone), findsNothing, reason: '"$gone" should be gone');
    }
  });

  testWidgets('shows the streak line from the summary doc', (tester) async {
    final auth = signedInAuth();
    final firestore = await seed(auth);
    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({'streak': 12});
    await openSheet(tester, auth: auth, firestore: firestore);

    expect(find.text('12-day streak'), findsOneWidget);
  });

  testWidgets('lists at most 3 unread notifications and counts them all', (
    tester,
  ) async {
    final auth = signedInAuth();
    final firestore = await seed(auth, unread: 5, read: 2);
    await openSheet(tester, auth: auth, firestore: firestore);

    expect(find.text('NOTIFICATIONS · 5 NEW'), findsOneWidget);
    expect(find.textContaining('Unread message'), findsNWidgets(3));
    // Newest first.
    expect(find.text('Unread message 4'), findsOneWidget);
    expect(find.text('Unread message 0'), findsNothing);
    expect(find.textContaining('Read message'), findsNothing);
  });

  testWidgets('See all opens the notification center', (tester) async {
    final auth = signedInAuth();
    final firestore = await seed(auth, unread: 1);
    await openSheet(tester, auth: auth, firestore: firestore);

    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();

    expect(find.byType(AppMenuSheet), findsNothing);
    expect(find.byType(NotificationCenterPage), findsOneWidget);
  });

  testWidgets('tapping a notification marks it read and closes the sheet', (
    tester,
  ) async {
    final auth = signedInAuth();
    final firestore = await seed(auth, unread: 2);
    await openSheet(tester, auth: auth, firestore: firestore);

    await tester.tap(find.text('Unread message 1'));
    await tester.pumpAndSettle();

    expect(find.byType(AppMenuSheet), findsNothing);
    final doc = await firestore
        .collection('users')
        .doc('u1')
        .collection('notifications')
        .doc('unread-1')
        .get();
    expect(doc.data()!['read'], isTrue);
  });

  testWidgets('tapping a join-request notification still routes by groupId', (
    tester,
  ) async {
    final auth = signedInAuth();
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('groups').doc('g1').set({
      'name': 'Group',
      'ownerId': 'u1',
      'members': ['u1'],
    });
    await NotificationService(firestore: firestore).addNotification(
      'u1',
      AppNotification(
        id: 'join',
        type: NotificationType.groupJoinRequest,
        groupId: 'g1',
        message: 'Sam wants to join',
        timestamp: DateTime(2026, 1, 1),
        read: false,
      ),
    );
    await openSheet(tester, auth: auth, firestore: firestore);

    await tester.tap(find.text('Sam wants to join'));
    await tester.pumpAndSettle();

    expect(find.byType(GroupJoinRequestsPage), findsOneWidget);
  });

  testWidgets('Settings opens the settings page', (tester) async {
    final auth = signedInAuth();
    final firestore = await seed(auth);
    await openSheet(tester, auth: auth, firestore: firestore);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.byType(AppMenuSheet), findsNothing);
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('shows Inbox with an Admin tag only for admins', (tester) async {
    final auth = signedInAuth();
    final firestore = await seed(auth);
    await openSheet(
      tester,
      auth: auth,
      firestore: firestore,
      admin: _AlwaysAdminService(),
    );

    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);

    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    expect(find.byType(FeedbackAdminPage), findsOneWidget);
  });

  testWidgets('hides Inbox for non-admins', (tester) async {
    final auth = signedInAuth();
    final firestore = await seed(auth);
    await openSheet(tester, auth: auth, firestore: firestore);

    expect(find.text('Inbox'), findsNothing);
    expect(find.text('Admin'), findsNothing);
  });

  testWidgets('menu uses cached admin value without waiting for refresh', (
    tester,
  ) async {
    final adminRoleService = _StaleCachedAdminService(true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  AppMenuSheet.show(
                    context: context,
                    vibrationService: const VibrationService(),
                    adminRoleService: adminRoleService,
                  );
                },
                child: const Text('Open menu'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open menu'));
    await tester.pump();

    expect(find.byType(AppMenuSheet), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
  });
}

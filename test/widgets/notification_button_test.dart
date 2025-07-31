import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/notification_button.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:bible_read/models/app_notification.dart';
import 'package:bible_read/models/notification_preferences.dart';
import 'package:bible_read/pages/notification_center_page.dart';

class FakeNotificationService extends NotificationService {
  FakeNotificationService({required Stream<List<AppNotification>> stream})
      : stream = stream.asBroadcastStream(),
        super(firestore: FakeFirebaseFirestore());

  final Stream<List<AppNotification>> stream;

  @override
  Stream<List<AppNotification>> notifications(String uid) => stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders new icon and tooltip', (tester) async {
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    final service = FakeNotificationService(stream: Stream.value([]));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [
            NotificationButton(service: service, auth: auth),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.notifications), findsOneWidget);
    expect(find.byTooltip('Notifications'), findsOneWidget);
  });

  testWidgets('shows badge for unread notifications and navigates',
      (tester) async {
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u2'), signedIn: true);
    final n1 = AppNotification(
      id: 'n1',
      type: NotificationType.like,
      timestamp: DateTime.now(),
      read: false,
      senderUid: 'a',
    );
    final n2 = AppNotification(
      id: 'n2',
      type: NotificationType.signup,
      timestamp: DateTime.now(),
      read: true,
      senderUid: 'b',
    );
    final service = FakeNotificationService(stream: Stream.value([n1, n2]));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [
            NotificationButton(service: service, auth: auth),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<int>(1)), findsOneWidget);

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationCenterPage), findsOneWidget);
  });
}

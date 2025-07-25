import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/notification_button.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:bible_read/models/app_notification.dart';

class FakeNotificationService extends NotificationService {
  FakeNotificationService({required this.stream})
      : super(firestore: FakeFirebaseFirestore());
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
}

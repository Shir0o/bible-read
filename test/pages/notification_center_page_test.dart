import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bible_read/models/notification_preferences.dart';
import 'package:bible_read/pages/notification_center_page.dart';
import 'package:bible_read/services/notification_service.dart';

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
}

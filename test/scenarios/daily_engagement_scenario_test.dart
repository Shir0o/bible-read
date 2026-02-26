import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bible_read/pages/group_detail_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/models/group.dart';
import 'package:mocktail/mocktail.dart';
import 'package:network_image_mock/network_image_mock.dart';
import '../helpers/pump_app.dart';
import '../helpers/firebase_seeder.dart';
import '../helpers/mocks.dart';
import '../helpers/stub_vibration_service.dart';

void main() {
  testWidgets('Daily Engagement Scenario: User completes daily reading', (tester) async {
    await mockNetworkImagesFor(() async {
      // Setup
      final auth = MockFirebaseAuth(signedIn: false);
      final firestore = FakeFirebaseFirestore();
      final messaging = MockFirebaseMessaging();
      final functions = MockFirebaseFunctions();
      final vibration = StubVibrationService();
      final seeder = FirebaseSeeder(firestore);

      // Create services manually
      final notificationService = NotificationService(firestore: firestore);
      final groupService = GroupService(
          firestore: firestore, notificationService: notificationService);

      // Seed User
      final userCred = await auth.createUserWithEmailAndPassword(
          email: 'reader@example.com', password: 'password');
      final uid = userCred.user!.uid;
      await seeder.seedUser(uid: uid, name: 'Reader');

      // Seed Group
      final groupId = 'group123';
      await seeder.seedGroup(
        groupId: groupId,
        ownerUid: uid,
        name: 'Daily Readers',
        members: [uid],
      );

      // Seed Schedule for Today
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await seeder.seedGroupSchedule(
        groupId: groupId,
        schedule: [
          GroupSchedule(
            date: today,
            chapters: ['Gen 1', 'Gen 2'],
          ),
        ],
      );

      // Fetch Group object
      final groupSnap = await firestore.collection('groups').doc(groupId).get();
      final group = Group.fromFirestore(groupSnap);

      // Explicitly seed the progress entry doc
      final dateKey = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('progress')
          .doc(dateKey)
          .collection('entries')
          .doc(uid)
          .set({'done': false});

      // Pump GroupDetailPage
      await tester.pumpApp(
        GroupDetailPage(
          group: group,
          auth: auth,
          groupService: groupService,
          vibrationService: vibration,
        ),
      );
      await tester.pumpAndSettle();

      // Verify Today's Reading Section
      expect(find.text("Today's Reading"), findsOneWidget);
      expect(find.textContaining('Gen 1'), findsOneWidget);

      // Verify "Mark as Read" button text exists
      final markReadText = find.text('Mark as Read');
      expect(markReadText, findsOneWidget);

      // Tap it
      await tester.tap(markReadText);
      await tester.pumpAndSettle();

      // Verify it toggled to "Read"
      expect(find.text('Read'), findsOneWidget);

      // Verify Firestore update
      final entryDoc = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('progress')
          .doc(dateKey)
          .collection('entries')
          .doc(uid)
          .get();

      expect(entryDoc.exists, isTrue);
      expect(entryDoc.data()?['done'], isTrue);
    });
  });
}

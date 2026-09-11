import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:bible_read/pages/group_members_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:bible_read/services/nudge_service.dart';
import 'package:bible_read/models/group.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import '../helpers/pump_app.dart';
import '../helpers/firebase_seeder.dart';
import '../helpers/stub_vibration_service.dart';
import '../helpers/fake_google_sign_in_platform.dart';

void main() {
  setUpAll(() {
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();
  });

  testWidgets('Daily Engagement Scenario: GroupMembersPage shows member roster',
      (tester) async {
    await mockNetworkImagesFor(() async {
      // Setup
      final auth = MockFirebaseAuth(signedIn: false);
      final firestore = FakeFirebaseFirestore();
      final vibration = StubVibrationService();
      final seeder = FirebaseSeeder(firestore);

      // Create services manually
      final notificationService = NotificationService(firestore: firestore);
      final groupService = GroupService(
        firestore: firestore,
        notificationService: notificationService,
      );
      final nudgeService = NudgeService(firestore: firestore);

      // Seed User
      final userCred = await auth.createUserWithEmailAndPassword(
        email: 'reader@example.com',
        password: 'password',
      );
      final uid = userCred.user!.uid;
      await seeder.seedUser(uid: uid, name: 'Reader');

      // Seed Group with the user as a member
      final groupId = 'group123';
      await seeder.seedGroup(
        groupId: groupId,
        ownerUid: uid,
        name: 'Daily Readers',
        members: [uid],
      );

      // Fetch Group object
      final groupSnap = await firestore.collection('groups').doc(groupId).get();
      final group = Group.fromFirestore(groupSnap);

      // Pump GroupMembersPage
      await tester.pumpApp(
        GroupMembersPage(
          group: group,
          auth: auth,
          groupService: groupService,
          nudgeService: nudgeService,
          vibrationService: vibration,
        ),
      );
      await tester.pumpAndSettle();

      // Verify Members section header is shown
      expect(find.textContaining('Members'), findsAtLeastNWidgets(1));

      // Verify read-today summary label is shown
      expect(find.textContaining('read today'), findsOneWidget);
    });
  });
}

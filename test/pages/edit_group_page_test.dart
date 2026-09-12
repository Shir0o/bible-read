import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/models/group.dart';
import 'package:bible_read/pages/edit_group_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/services/error_logger.dart';
import 'package:bible_read/widgets/group_plan_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late Group group;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    group = const Group(id: 'g1', name: 'Study', ownerUid: 'u1');
    ErrorLogger.muteForTest = true;
  });

  Future<void> seedGroup() async {
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u1')
        .set({
      'uid': 'u1',
      'name': 'Owner',
      'role': 'owner',
      'joinedAt': Timestamp.now(),
    });
  }

  Future<void> pumpPage(
      WidgetTester tester, MockFirebaseAuth signedInAuth) async {
    auth = signedInAuth;
    await tester.pumpWidget(
      MaterialApp(
        home: EditGroupPage(
          group: group,
          groupService: GroupService(firestore: firestore),
          auth: auth,
          vibrationService: const VibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('owner sees group settings and no plan editor', (tester) async {
    await seedGroup();
    await pumpPage(
      tester,
      MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true),
    );

    expect(find.text('Group settings'), findsOneWidget);
    expect(find.byKey(const Key('group-settings-name')), findsOneWidget);
    expect(find.text('Public Group'), findsOneWidget);
    expect(find.text('Reschedule'), findsOneWidget);
    expect(find.text('Archive Group'), findsOneWidget);
    expect(find.text('Delete Group'), findsOneWidget);

    // The old shared plan editor is retired from this screen.
    expect(find.byKey(GroupPlanKeys.bookSearchField), findsNothing);
    expect(find.byKey(GroupPlanKeys.paceModeSegment), findsNothing);
    expect(find.byKey(GroupPlanKeys.submitButton), findsNothing);
  });

  testWidgets('member sees lifecycle actions but no Reschedule',
      (tester) async {
    await seedGroup();
    await pumpPage(
      tester,
      MockFirebaseAuth(mockUser: MockUser(uid: 'm2'), signedIn: true),
    );

    expect(find.text('Archive Participation'), findsOneWidget);
    expect(find.text('Leave Group'), findsOneWidget);
    expect(find.text('Reschedule'), findsNothing);
    expect(find.text('Archive Group'), findsNothing);
    expect(find.text('Delete Group'), findsNothing);
  });
}

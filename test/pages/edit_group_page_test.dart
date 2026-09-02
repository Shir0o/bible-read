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

  Future<void> pumpPage(WidgetTester tester) async {
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

  testWidgets('renders all sections', (tester) async {
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    // Add owner member so they show up
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u1')
        .set({
      'uid': 'u1',
      'name': 'Owner',
      'photoUrl': null,
      'role': 'owner',
      'joinedAt': Timestamp.now(),
    });

    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);

    await pumpPage(tester);

    // The shared form is in place — books search, pace, days, save button.
    expect(find.byKey(GroupPlanKeys.bookSearchField), findsOneWidget);
    expect(find.byKey(GroupPlanKeys.paceModeSegment), findsOneWidget);

    final scrollableFinder = find.byType(Scrollable).first;

    final membersFinder = find.text('Members');
    await tester.scrollUntilVisible(
      membersFinder,
      500,
      scrollable: scrollableFinder,
    );
    expect(membersFinder, findsOneWidget);

    final settingsFinder = find.text('Group Settings');
    await tester.scrollUntilVisible(
      settingsFinder,
      500,
      scrollable: scrollableFinder,
    );
    expect(settingsFinder, findsOneWidget);

    expect(find.byKey(GroupPlanKeys.submitButton), findsOneWidget);
  });
}

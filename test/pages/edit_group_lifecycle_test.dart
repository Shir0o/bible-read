// Role-based group lifecycle in EditGroupPage (#776): the owner gets
// Archive Group and Delete Group; a non-owner member gets Archive
// Participation and Leave Group — and only their own participation changes.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group.dart';
import 'package:bible_read/pages/edit_group_page.dart';
import 'package:bible_read/services/error_logger.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/vibration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  late FakeFirebaseFirestore firestore;
  late GroupService groupService;
  late Group group;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    groupService = GroupService(firestore: firestore);
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
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('m2')
        .set({
      'uid': 'm2',
      'name': 'Member Two',
      'role': 'member',
      'joinedAt': Timestamp.now(),
    });
  }

  Future<void> pumpPage(WidgetTester tester, MockFirebaseAuth auth) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EditGroupPage(
          group: group,
          groupService: groupService,
          auth: auth,
          vibrationService: const VibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollToSettings(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Group Settings'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
  }

  testWidgets(
      'owner sees Archive Group and Delete Group and archiving '
      'shelves the group without destroying it', (tester) async {
    await seedGroup();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await pumpPage(tester, auth);
    await scrollToSettings(tester);

    expect(find.text('Archive Group'), findsOneWidget);
    expect(find.text('Delete Group'), findsOneWidget);
    expect(find.text('Archive Participation'), findsNothing);
    expect(find.text('Leave Group'), findsNothing);

    // Archive the group.
    await tester.tap(find.text('Archive Group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    final doc = await firestore.collection('groups').doc('g1').get();
    expect(doc.exists, isTrue);
    expect(doc.data()?['isArchived'], isTrue);
    expect(doc.data()?['deletedAt'], isNull);

    // Shelved: gone from the live list, present in the archive listing.
    expect(await groupService.groupsForUser('u1').first, isEmpty);
    final archived = await groupService.archivedGroupsForUser('u1');
    expect(archived.single.id, 'g1');
  });

  testWidgets('owner Delete Group soft-deletes with a 30-day deadline',
      (tester) async {
    await seedGroup();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await pumpPage(tester, auth);
    await scrollToSettings(tester);
    await tester.ensureVisible(find.text('Delete Group'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete Group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    final doc = await firestore.collection('groups').doc('g1').get();
    expect(doc.exists, isTrue);
    expect(doc.data()?['deletedAt'], isNotNull);
    expect(doc.data()?['deleteAfter'], isNotNull);
    expect(doc.data()?['preDeleteState'], 'active');
    expect(await groupService.groupsForUser('u1').first, isEmpty);
  });

  testWidgets(
      'member sees Archive Participation and Leave Group, and '
      'archiving participation touches only their membership', (tester) async {
    await seedGroup();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'm2'), signedIn: true);
    await pumpPage(tester, auth);
    await scrollToSettings(tester);

    expect(find.text('Archive Participation'), findsOneWidget);
    expect(find.text('Leave Group'), findsOneWidget);
    expect(find.text('Archive Group'), findsNothing);
    expect(find.text('Delete Group'), findsNothing);

    await tester.tap(find.text('Archive Participation'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    // The member's participation is archived; the group itself untouched.
    final memberDoc = await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('m2')
        .get();
    expect(memberDoc.data()?['isArchived'], isTrue);
    final groupDoc = await firestore.collection('groups').doc('g1').get();
    // The group itself was never touched: no lifecycle fields written.
    expect(groupDoc.data()?.containsKey('isArchived'), isFalse);
    expect(groupDoc.data()?['deletedAt'], isNull);

    // The member's live list hides it; the owner's still shows it.
    expect(await groupService.groupsForUser('m2').first, isEmpty);
    expect(await groupService.groupsForUser('u1').first, hasLength(1));
    final archived = await groupService.archivedGroupsForUser('m2');
    expect(archived.single.id, 'g1');
  });

  testWidgets('member Leave Group removes only their membership',
      (tester) async {
    await seedGroup();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'm2'), signedIn: true);
    await pumpPage(tester, auth);
    await scrollToSettings(tester);
    await tester.ensureVisible(find.text('Leave Group'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Leave Group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    // The member is gone; the group survives for the owner.
    final memberDoc = await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('m2')
        .get();
    expect(memberDoc.exists, isFalse);
    final groupDoc = await firestore.collection('groups').doc('g1').get();
    expect(groupDoc.exists, isTrue);
    expect(await groupService.groupsForUser('u1').first, hasLength(1));
  });
}

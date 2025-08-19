import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/groups_page.dart';
import 'package:bible_read/services/group_service.dart';

class RecordingGroupService extends GroupService {
  RecordingGroupService({required super.firestore});

  String? createdName;
  String? createdOwner;
  bool? createdIsPublic;
  bool failCreate = false;

  @override
  Future<String> createGroup({
    required String ownerUid,
    required String name,
    bool isPublic = true,
  }) async {
    if (failCreate) {
      throw FirebaseException(plugin: 'firestore');
    }
    createdName = name;
    createdOwner = ownerUid;
    createdIsPublic = isPublic;
    return 'gid';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1', displayName: 'Test User'),
      signedIn: true,
    );
  });

  Future<void> pumpPage(WidgetTester tester, GroupService service) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GroupsPage(groupService: service, auth: auth),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists all groups from service', (tester) async {
    await firestore.collection('groups').doc('g1').set({
      'name': 'Study',
      'ownerUid': 'u1',
    });
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('m1')
        .set({
          'uid': 'u1',
          'role': 'owner',
          'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
        });
    await firestore.collection('groups').doc('g2').set({
      'name': 'Other',
      'ownerUid': 'u2',
    });

    await pumpPage(tester, GroupService(firestore: firestore));

    expect(find.text('Study'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
  });

  testWidgets('shows joined and pending indicators', (tester) async {
    await firestore.collection('groups').doc('g1').set({
      'name': 'Study',
      'ownerUid': 'u1',
    });
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u1')
        .set({
          'uid': 'u1',
          'role': 'member',
          'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
        });
    await firestore.collection('groups').doc('g2').set({
      'name': 'Other',
      'ownerUid': 'u2',
    });
    await firestore
        .collection('groups')
        .doc('g2')
        .collection('joinRequests')
        .doc('u1')
        .set({'uid': 'u1'});

    await pumpPage(tester, GroupService(firestore: firestore));

    final joinedTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Study'),
    );
    expect((joinedTile.trailing as Icon).icon, Icons.check);

    final pendingTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Other'),
    );
    expect((pendingTile.trailing as Text).data, 'Pending');
  });

  testWidgets('create group success shows snackbar', (tester) async {
    final service = RecordingGroupService(firestore: firestore);
    await pumpPage(tester, service);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'New');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(service.createdName, 'New');
    expect(service.createdOwner, 'u1');
    expect(find.text('Group created'), findsOneWidget);
  });

  testWidgets('create group failure shows error', (tester) async {
    final service = RecordingGroupService(firestore: firestore)
      ..failCreate = true;
    await pumpPage(tester, service);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'New');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(
      find.text('Failed to create group. Please try again.'),
      findsOneWidget,
    );
  });
}

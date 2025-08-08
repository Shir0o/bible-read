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
  String? joinGroupId;
  String? joinUid;
  bool failCreate = false;
  bool failJoin = false;

  @override
  Future<String> createGroup(
      {required String ownerUid, required String name}) async {
    if (failCreate) {
      throw FirebaseException(plugin: 'firestore');
    }
    createdName = name;
    createdOwner = ownerUid;
    return 'gid';
  }

  @override
  Future<void> joinGroup({required String groupId, required String uid}) async {
    if (failJoin) {
      throw FirebaseException(plugin: 'firestore');
    }
    joinGroupId = groupId;
    joinUid = uid;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
  });

  Future<void> pumpPage(WidgetTester tester, GroupService service) async {
    await tester.pumpWidget(
      MaterialApp(home: GroupsPage(groupService: service, auth: auth)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists groups from service', (tester) async {
    await firestore.collection('groups').doc('g1').set({
      'name': 'Study',
      'ownerUid': 'u1',
    });
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u1')
        .set({'owner': true});

    await pumpPage(tester, GroupService(firestore: firestore));

    expect(find.text('Study'), findsOneWidget);
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
        find.text('Failed to create group. Please try again.'), findsOneWidget);
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/groups_page.dart';
import 'package:bible_read/pages/create_group_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/vibration_service.dart';

class RecordingGroupService extends GroupService {
  RecordingGroupService({required super.firestore});

  String? createdName;
  String? createdOwner;
  bool failCreate = false;

  @override
  Future<String> createGroup({
    required String ownerUid,
    required String name,
    bool isPublic = false,
  }) async {
    if (failCreate) {
      throw FirebaseException(plugin: 'firestore');
    }
    createdName = name;
    createdOwner = ownerUid;
    return 'gid';
  }
}

class _RecordingVibrationService extends VibrationService {
  int lightCount = 0;

  @override
  Future<void> lightImpact() async {
    lightCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late _RecordingVibrationService vibration;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1', displayName: 'Test User'),
      signedIn: true,
    );
    vibration = _RecordingVibrationService();
  });

  Future<void> pumpPage(WidgetTester tester, GroupService service) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GroupsPage(
          groupService: service,
          auth: auth,
          vibrationService: vibration,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists all groups from service', (tester) async {
    await firestore.collection('groups').doc('g1').set({
      'name': 'Study',
      'ownerUid': 'u1',
      'memberCount': 1,
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
      'memberCount': 1,
    });
    await firestore
        .collection('groups')
        .doc('g2')
        .collection('members')
        .doc('u1')
        .set({
          'uid': 'u1',
          'role': 'member',
          'joinedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 2)),
        });

    await pumpPage(tester, GroupService(firestore: firestore));

    expect(find.text('Study'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
  });

  testWidgets('shows pending indicator (no joined checkmark)', (tester) async {
    await firestore.collection('groups').doc('g1').set({
      'name': 'Study',
      'ownerUid': 'u1',
      'memberCount': 2,
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
      'memberCount': 3,
    });
    await firestore
        .collection('groups')
        .doc('g2')
        .collection('joinRequests')
        .doc('u1')
        .set({'uid': 'u1'});

    await pumpPage(tester, GroupService(firestore: firestore));

    expect(find.text('Study'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
  });

  testWidgets('navigates to create group page', (tester) async {
    final service = RecordingGroupService(firestore: firestore);
    await pumpPage(tester, service);

    await tester.tap(find.text('Join or Create Group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create New Group'));
    await tester.pumpAndSettle();

    expect(find.byType(CreateGroupPage), findsOneWidget);
    expect(find.text('New Group Plan'), findsOneWidget);
  });

  testWidgets('shows empty state with create button when no groups exist', (
    tester,
  ) async {
    final service = RecordingGroupService(firestore: firestore);
    await pumpPage(tester, service);

    expect(find.text('You haven\'t joined any groups yet.'), findsOneWidget);
    expect(find.text('Join or Create Group'), findsOneWidget);
    expect(find.byIcon(Icons.add_circle), findsOneWidget);

    await tester.tap(find.text('Join or Create Group'));
    await tester.pumpAndSettle();

    // Verify Bottom Sheet options
    expect(find.text('Create New Group'), findsOneWidget);
    expect(find.text('Find a Group'), findsOneWidget);

    await tester.tap(find.text('Create New Group'));
    await tester.pumpAndSettle();

    expect(find.byType(CreateGroupPage), findsOneWidget);
  });
}

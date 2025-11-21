import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/groups_page.dart';
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
      'memberCount': 0,
    });

    await pumpPage(tester, GroupService(firestore: firestore));

    expect(find.text('Study'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);

    final studyTile = tester.widget<ListTile>(
      find
          .ancestor(
            of: find.text('Study'),
            matching: find.byType(ListTile),
          )
          .first,
    );
    final otherTile = tester.widget<ListTile>(
      find
          .ancestor(
            of: find.text('Other'),
            matching: find.byType(ListTile),
          )
          .first,
    );

    expect((studyTile.subtitle as Text).data, '1 member');
    expect(studyTile.trailing, isNull);

    expect((otherTile.subtitle as Text).data, '1 member');
    expect(otherTile.trailing, isNull);
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

    final joinedTile = tester.widget<ListTile>(
      find
          .ancestor(
            of: find.text('Study'),
            matching: find.byType(ListTile),
          )
          .first,
    );
    expect(joinedTile.trailing, isNull);

    final pendingTile = tester.widget<ListTile>(
      find
          .ancestor(
            of: find.text('Other'),
            matching: find.byType(ListTile),
          )
          .first,
    );
    expect((pendingTile.trailing as Text).data, 'Pending');
    expect((joinedTile.subtitle as Text).data, '1 member');
    expect((pendingTile.subtitle as Text).data, '1 member');
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
    expect(vibration.lightCount, 1);
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
    expect(vibration.lightCount, 1);
  });

  testWidgets('cancel create disposes controller safely', (tester) async {
    final service = RecordingGroupService(firestore: firestore);
    await pumpPage(tester, service);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(service.createdName, isNull);
    expect(service.createdOwner, isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    expect(vibration.lightCount, 1);
  });
}

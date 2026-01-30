import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/group_join_requests_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/vibration_service.dart';

class _RecordingGroupService extends GroupService {
  _RecordingGroupService({required super.firestore});

  bool approveCalled = false;
  bool denyCalled = false;

  @override
  Future<void> approveJoinRequest({
    required String groupId,
    required String uid,
  }) async {
    approveCalled = true;
    return super.approveJoinRequest(groupId: groupId, uid: uid);
  }

  @override
  Future<void> denyJoinRequest({
    required String groupId,
    required String uid,
  }) async {
    denyCalled = true;
    return super.denyJoinRequest(groupId: groupId, uid: uid);
  }
}

class _StubVibrationService extends VibrationService {
  int lightImpactCount = 0;

  @override
  Future<void> lightImpact() async {
    lightImpactCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late _StubVibrationService vibration;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'owner'), signedIn: true);
    vibration = _StubVibrationService();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    GroupService? groupService,
    required String groupId,
    Stream<QuerySnapshot<Map<String, dynamic>>>? joinRequestsStream,
  }) async {
    final resolvedService = groupService ?? GroupService(firestore: firestore);
    await tester.pumpWidget(
      MaterialApp(
        home: GroupJoinRequestsPage(
          groupId: groupId,
          groupService: resolvedService,
          auth: auth,
          vibrationService: vibration,
          joinRequestsStream: joinRequestsStream,
        ),
      ),
    );
  }

  testWidgets('shows loading indicator before data arrives', (tester) async {
    final groupId = 'g1';

    await pumpPage(
      tester,
      groupId: groupId,
      groupService: GroupService(firestore: firestore),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('shows empty state when no join requests exist', (tester) async {
    final groupId = 'g2';

    await firestore.collection(GroupCollections.groups).doc(groupId).set({
      'name': 'Test',
      'ownerUid': 'owner',
      'memberCount': 1,
    });

    await pumpPage(
      tester,
      groupId: groupId,
      groupService: GroupService(firestore: firestore),
    );

    await tester.pumpAndSettle();

    expect(find.text('No pending requests'), findsOneWidget);
  });

  testWidgets('shows error UI when stream emits error', (tester) async {
    final controller =
        StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();
    addTearDown(controller.close);

    await pumpPage(
      tester,
      groupId: 'g-error',
      joinRequestsStream: controller.stream,
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    controller.addError(Exception('boom'));
    await tester.pump();

    expect(find.text('Failed to load join requests'), findsOneWidget);
  });

  testWidgets('approving request updates service and shows snackbar',
      (tester) async {
    const groupId = 'g-approve';
    const uid = 'alice';

    await firestore.collection(GroupCollections.groups).doc(groupId).set({
      'name': 'Group',
      'ownerUid': 'owner',
      'memberCount': 1,
    });
    await firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.joinRequests)
        .doc(uid)
        .set({
      'uid': uid,
      'name': 'Alice',
    });

    final service = _RecordingGroupService(firestore: firestore);

    await pumpPage(
      tester,
      groupId: groupId,
      groupService: service,
    );

    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);

    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.label == 'Approve join request from Alice'));
    await tester.pumpAndSettle();

    expect(service.approveCalled, isTrue);
    expect(find.text('Request approved'), findsOneWidget);

    final requestSnap = await firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.joinRequests)
        .doc(uid)
        .get();
    expect(requestSnap.exists, isFalse);

    final memberSnap = await firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.members)
        .doc(uid)
        .get();
    expect(memberSnap.exists, isTrue);
  });

  testWidgets('denying request updates service and shows snackbar',
      (tester) async {
    const groupId = 'g-deny';
    const uid = 'eve';

    await firestore.collection(GroupCollections.groups).doc(groupId).set({
      'name': 'Group',
      'ownerUid': 'owner',
      'memberCount': 1,
    });
    await firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.joinRequests)
        .doc(uid)
        .set({
      'uid': uid,
      'name': 'Eve',
    });

    final service = _RecordingGroupService(firestore: firestore);

    await pumpPage(
      tester,
      groupId: groupId,
      groupService: service,
    );

    await tester.pumpAndSettle();

    expect(find.text('Eve'), findsOneWidget);

    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.label == 'Deny join request from Eve'));
    await tester.pumpAndSettle();

    expect(service.denyCalled, isTrue);
    expect(find.text('Request denied'), findsOneWidget);

    final requestSnap = await firestore
        .collection(GroupCollections.groups)
        .doc(groupId)
        .collection(GroupCollections.joinRequests)
        .doc(uid)
        .get();
    expect(requestSnap.exists, isFalse);
  });
}

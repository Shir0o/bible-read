import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import 'package:bible_read/models/group.dart';
import 'package:bible_read/pages/group_detail_page.dart';
import 'package:bible_read/pages/join_by_code_page.dart';
import 'package:bible_read/pages/share_code_page.dart';
import 'package:bible_read/services/error_logger.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/widgets/join_code_keys.dart';
import '../helpers/stub_vibration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
    ErrorLogger.muteForTest = true;
  });

  late FakeFirebaseFirestore firestore;
  late GroupService groupService;
  late StubVibrationService vibration;
  late MockFirebaseAuth ownerAuth;
  late MockFirebaseAuth joinerAuth;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    groupService = GroupService(firestore: firestore);
    vibration = StubVibrationService();
    ownerAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'owner-uid', displayName: 'Owner'),
      signedIn: true,
    );
    joinerAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'joiner-uid', displayName: 'Joiner'),
      signedIn: true,
    );
  });

  Future<void> pumpUntilSettled(
    WidgetTester tester, {
    Duration step = const Duration(milliseconds: 50),
    int maxSteps = 200,
  }) async {
    final binding = tester.binding;
    for (var i = 0; i < maxSteps; i++) {
      await tester.pump(step);
      if (!binding.hasScheduledFrame && binding.transientCallbackCount == 0) {
        return;
      }
    }
    await tester.pump();
  }

  Future<void> pumpDetailPage(
    WidgetTester tester,
    Group group,
    MockFirebaseAuth auth,
  ) async {
    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: GroupDetailPage(
            group: group,
            groupService: groupService,
            auth: auth,
            vibrationService: vibration,
          ),
        ),
      );
    });
    await pumpUntilSettled(tester);
  }

  Future<void> pumpJoinPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: JoinByCodePage(
          groupService: groupService,
          auth: joinerAuth,
          vibrationService: vibration,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterAndFind(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(JoinCodeKeys.codeField), code);
    await tester.tap(find.byKey(JoinCodeKeys.findButton));
    await tester.pumpAndSettle();
  }

  Future<String> seedPublicGroup() async {
    final groupId = await groupService.createGroup(
      ownerUid: 'owner-uid',
      name: 'Evening Readers',
      isPublic: true,
    );
    return groupId;
  }

  testWidgets('a member opens Share code and sees a code', (tester) async {
    final groupId = await seedPublicGroup();

    await pumpDetailPage(
      tester,
      Group(
        id: groupId,
        name: 'Evening Readers',
        ownerUid: 'owner-uid',
        memberCount: 1,
      ),
      ownerAuth,
    );
    await tester.tap(find.byTooltip('Share code'));
    await pumpUntilSettled(tester);

    expect(find.byType(ShareCodePage), findsOneWidget);
    final code = tester.widget<Text>(find.byKey(JoinCodeKeys.codeText)).data!;
    expect(code, hasLength(6));
  });

  testWidgets('a second reader redeems the code and lands in the group',
      (tester) async {
    final groupId = await seedPublicGroup();
    final code = await groupService.joinCodeService.ensureGroupCode(groupId);

    // A wrong code shows a clear error rather than failing silently.
    await pumpJoinPage(tester);
    await enterAndFind(tester, 'ZZZZZZ');
    expect(find.byKey(JoinCodeKeys.errorText), findsOneWidget);
    expect(find.byKey(JoinCodeKeys.previewCard), findsNothing);

    // The shared code, typed lowercase with a dash, previews the group's
    // name and size before committing.
    final messy =
        ' ${code.substring(0, 3).toLowerCase()}-${code.substring(3)} ';
    await enterAndFind(tester, messy);
    expect(find.text('Evening Readers'), findsOneWidget);
    expect(find.text('1 member'), findsOneWidget);

    // Confirming lands the reader in the group.
    await tester.tap(find.byKey(JoinCodeKeys.confirmButton));
    await tester.pumpAndSettle();
    final member = await firestore
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc('joiner-uid')
        .get();
    expect(member.exists, isTrue);
    final groupDoc = await firestore.collection('groups').doc(groupId).get();
    expect(groupDoc.data()?['memberCount'], 2);
  });

  testWidgets('entering the code of a group you are already in says so',
      (tester) async {
    final groupId = await seedPublicGroup();
    final code = await groupService.joinCodeService.ensureGroupCode(groupId);
    await groupService.joinGroupDirectly(
      groupId: groupId,
      uid: 'joiner-uid',
      name: 'Joiner',
    );

    await pumpJoinPage(tester);
    await enterAndFind(tester, code);
    expect(find.text("You're already in this group"), findsOneWidget);
    expect(find.byKey(JoinCodeKeys.confirmButton), findsNothing);
    final memberDocs = await firestore
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .get();
    expect(memberDocs.docs, hasLength(2));
  });

  testWidgets('a non-owner member can reach Share code', (tester) async {
    final groupId = await seedPublicGroup();
    await groupService.joinGroupDirectly(
      groupId: groupId,
      uid: 'joiner-uid',
      name: 'Joiner',
    );

    await pumpDetailPage(
      tester,
      Group(
        id: groupId,
        name: 'Evening Readers',
        ownerUid: 'owner-uid',
        memberCount: 2,
      ),
      joinerAuth,
    );
    expect(find.byTooltip('Share code'), findsOneWidget);
  });
}

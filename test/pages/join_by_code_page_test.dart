import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/join_by_code_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/join_code_service.dart';
import 'package:bible_read/widgets/join_code_keys.dart';
import '../helpers/stub_vibration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late GroupService groupService;
  late MockFirebaseAuth auth;
  late StubVibrationService vibration;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    groupService = GroupService(firestore: firestore);
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'joiner', displayName: 'Joiner'),
      signedIn: true,
    );
    vibration = StubVibrationService();
  });

  Future<String> seedCodedGroup({bool isPublic = false}) async {
    final groupId = await groupService.createGroup(
      ownerUid: 'owner',
      name: 'Evening Readers',
      isPublic: isPublic,
    );
    return groupId;
  }

  Future<void> pumpPage(WidgetTester tester, String code) async {
    await tester.pumpWidget(
      MaterialApp(
        home: JoinByCodePage(
          groupService: groupService,
          auth: auth,
          vibrationService: vibration,
        ),
      ),
    );
    await tester.enterText(find.byKey(JoinCodeKeys.codeField), code);
    await tester.tap(find.byKey(JoinCodeKeys.findButton));
    await tester.pumpAndSettle();
  }

  testWidgets('an unknown code shows a clear error', (tester) async {
    await pumpPage(tester, 'ZZZZZZ');

    expect(find.byKey(JoinCodeKeys.errorText), findsOneWidget);
    expect(find.byKey(JoinCodeKeys.previewCard), findsNothing);
  });

  testWidgets(
      'a found group is previewed with its name and size before joining',
      (tester) async {
    final groupId = await seedCodedGroup();
    final code = await firestore
        .collection('groups')
        .doc(groupId)
        .get()
        .then((doc) => doc.data()!['joinCode'] as String);

    await pumpPage(tester, code);

    expect(find.byKey(JoinCodeKeys.previewCard), findsOneWidget);
    expect(find.text('Evening Readers'), findsOneWidget);
    expect(find.text('1 member'), findsOneWidget);
    expect(find.byKey(JoinCodeKeys.confirmButton), findsOneWidget);
  });

  testWidgets('a lowercase code with spaces and dashes still resolves',
      (tester) async {
    final groupId = await seedCodedGroup();
    final code = await firestore
        .collection('groups')
        .doc(groupId)
        .get()
        .then((doc) => doc.data()!['joinCode'] as String);
    final messy =
        ' ${code.substring(0, 3).toLowerCase()}-${code.substring(3)} ';

    await pumpPage(tester, messy);

    expect(find.text('Evening Readers'), findsOneWidget);
  });

  testWidgets('a group joins directly on confirm', (tester) async {
    final groupId = await seedCodedGroup();
    final code = await firestore
        .collection('groups')
        .doc(groupId)
        .get()
        .then((doc) => doc.data()!['joinCode'] as String);

    await pumpPage(tester, code);
    await tester.tap(find.byKey(JoinCodeKeys.confirmButton));
    await tester.pumpAndSettle();

    final member = await firestore
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc('joiner')
        .get();
    expect(member.exists, isTrue);
    final group = await firestore.collection('groups').doc(groupId).get();
    expect(group.data()?['memberCount'], 2);
  });

  testWidgets('entering the code of a group you are already in says so',
      (tester) async {
    final groupId = await seedCodedGroup();
    await groupService.joinGroup(
      groupId: groupId,
      uid: 'joiner',
      name: 'Joiner',
    );
    final code = await firestore
        .collection('groups')
        .doc(groupId)
        .get()
        .then((doc) => doc.data()!['joinCode'] as String);

    await pumpPage(tester, code);

    expect(find.byKey(JoinCodeKeys.memberNote), findsOneWidget);
    expect(find.text("You're already in this group"), findsOneWidget);
    expect(find.byKey(JoinCodeKeys.confirmButton), findsNothing);
  });

  testWidgets('a pasted group share message reaches the group preview',
      (tester) async {
    final groupId = await seedCodedGroup(isPublic: true);
    final code = await groupService.joinCodeService.ensureGroupCode(groupId);

    await tester.pumpWidget(
      MaterialApp(
        home: JoinByCodePage(
          groupService: groupService,
          auth: auth,
          vibrationService: vibration,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(JoinCodeKeys.codeField),
      'Join my group "Evening Readers" on Bible Reading Challenge: '
      '${JoinCodeService.shareLink(code)}',
    );
    await tester.tap(find.byKey(JoinCodeKeys.findButton));
    await tester.pumpAndSettle();

    expect(find.byKey(JoinCodeKeys.previewCard), findsOneWidget);
    expect(find.text('Evening Readers'), findsOneWidget);
  });

  testWidgets('initialCode resolves immediately on open', (tester) async {
    final groupId = await seedCodedGroup(isPublic: true);
    final code = await groupService.joinCodeService.ensureGroupCode(groupId);

    await tester.pumpWidget(
      MaterialApp(
        home: JoinByCodePage(
          groupService: groupService,
          auth: auth,
          vibrationService: vibration,
          initialCode: code,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(JoinCodeKeys.previewCard), findsOneWidget);
    expect(find.text('Evening Readers'), findsOneWidget);
  });
}

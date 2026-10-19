import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/join_by_code_page.dart';
import 'package:bible_read/services/friend_invite.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/widgets/friend_code_keys.dart';
import 'package:bible_read/widgets/join_code_keys.dart';
import '../helpers/stub_vibration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late GroupService groupService;
  late FriendService friendService;
  late MockFirebaseAuth auth;
  late StubVibrationService vibration;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    groupService = GroupService(firestore: firestore);
    friendService = FriendService(firestore: firestore);
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

  testWidgets('a public group joins directly on confirm', (tester) async {
    final groupId = await seedCodedGroup(isPublic: true);
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

  testWidgets('a private group creates a join request on confirm',
      (tester) async {
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
    expect(member.exists, isFalse);
    final request = await firestore
        .collection('groups')
        .doc(groupId)
        .collection('joinRequests')
        .doc('joiner')
        .get();
    expect(request.exists, isTrue);
  });

  testWidgets('entering the code of a group you are already in says so',
      (tester) async {
    final groupId = await seedCodedGroup();
    await groupService.joinGroupDirectly(
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
    // No re-join affordance exists for a group you are already in.
    expect(find.byKey(JoinCodeKeys.confirmButton), findsNothing);
  });

  Future<void> pumpFriendPage(
    WidgetTester tester,
    String code, {
    FriendService? service,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: JoinByCodePage(
          groupService: groupService,
          auth: auth,
          vibrationService: vibration,
          friendService: service ?? friendService,
        ),
      ),
    );
    await tester.enterText(find.byKey(JoinCodeKeys.codeField), code);
    await tester.tap(find.byKey(JoinCodeKeys.findButton));
    await tester.pumpAndSettle();
  }

  testWidgets('an eight-character code routes to the friend preview',
      (tester) async {
    await firestore.collection('users').doc('owner').set({'name': 'Mei'});
    final code = await friendService.ensureMyCode('owner');

    await pumpFriendPage(tester, code);

    expect(find.byKey(FriendCodeKeys.previewCard), findsOneWidget);
    expect(find.text('Mei'), findsOneWidget);
    expect(find.text('Friend code'), findsOneWidget);
    expect(find.byKey(JoinCodeKeys.previewCard), findsNothing);
    expect(find.text('Add Mei as a friend'), findsOneWidget);
  });

  testWidgets('confirming redeems the normalised friend code', (tester) async {
    await firestore.collection('users').doc('owner').set({'name': 'Mei'});
    final code = await friendService.ensureMyCode('owner');
    String? redeemed;
    final service = FriendService(
      firestore: firestore,
      redeemFriendCodeFn: (raw) async {
        redeemed = raw;
        return FriendRedemption.added;
      },
    );

    await pumpFriendPage(tester, code.toLowerCase(), service: service);
    await tester.tap(find.byKey(FriendCodeKeys.confirmButton));
    await tester.pumpAndSettle();

    expect(redeemed, code);
    expect(find.text('You’re now friends with Mei'), findsOneWidget);
  });

  testWidgets('entering your own friend code explains why nothing happened',
      (tester) async {
    await firestore.collection('users').doc('owner').set({'name': 'Mei'});
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'owner', displayName: 'Mei'),
      signedIn: true,
    );
    final code = await friendService.ensureMyCode('owner');

    await pumpFriendPage(tester, code);

    expect(find.byKey(FriendCodeKeys.previewCard), findsNothing);
    expect(
      find.text("That's your own code. Share it with someone instead."),
      findsOneWidget,
    );
  });

  testWidgets('an existing Friend is reported instead of previewed',
      (tester) async {
    await firestore.collection('users').doc('owner').set({'name': 'Mei'});
    final code = await friendService.ensureMyCode('owner');
    await firestore
        .collection('users')
        .doc('joiner')
        .collection('friends')
        .doc('owner')
        .set({'uid': 'owner'});

    await pumpFriendPage(tester, code);

    expect(find.byKey(FriendCodeKeys.previewCard), findsNothing);
    expect(find.text('You’re already friends with Mei.'), findsOneWidget);
  });

  testWidgets('an unknown eight-character code says so', (tester) async {
    await pumpFriendPage(tester, 'ZZZZZZZZ');

    expect(find.byKey(JoinCodeKeys.errorText), findsOneWidget);
    expect(find.byKey(FriendCodeKeys.previewCard), findsNothing);
  });

  group('add side', () {
    Future<ValueChanged<String>> pumpWithScanner(WidgetTester tester) async {
      late ValueChanged<String> emit;
      await tester.pumpWidget(
        MaterialApp(
          home: JoinByCodePage(
            groupService: groupService,
            auth: auth,
            vibrationService: vibration,
            friendService: friendService,
            title: 'Their code',
            scanViewBuilder: (context, onDetect) {
              emit = onDetect;
              return const ColoredBox(color: Colors.black);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return emit;
    }

    testWidgets('a scanned friend payload reaches the confirm card',
        (tester) async {
      await firestore.collection('users').doc('owner').set({'name': 'Mei'});
      final code = await friendService.ensureMyCode('owner');

      final emit = await pumpWithScanner(tester);
      emit(code);
      await tester.pumpAndSettle();

      expect(find.byKey(FriendCodeKeys.previewCard), findsOneWidget);
      expect(find.text('Add Mei as a friend'), findsOneWidget);
    });

    testWidgets('a scanned group payload reaches the group preview',
        (tester) async {
      final groupId = await seedCodedGroup();
      final code = await firestore
          .collection('groups')
          .doc(groupId)
          .get()
          .then((doc) => doc.data()!['joinCode'] as String);

      final emit = await pumpWithScanner(tester);
      emit(code);
      await tester.pumpAndSettle();

      expect(find.byKey(JoinCodeKeys.previewCard), findsOneWidget);
      expect(find.text('Evening Readers'), findsOneWidget);
      expect(find.byKey(FriendCodeKeys.previewCard), findsNothing);
    });

    testWidgets('a payload that is not a code says so', (tester) async {
      final emit = await pumpWithScanner(tester);

      emit('hello there');
      await tester.pumpAndSettle();

      expect(find.text('Not a Bible Read code.'), findsOneWidget);
    });

    testWidgets('a pasted invite link reaches the confirm card',
        (tester) async {
      await firestore.collection('users').doc('owner').set({'name': 'Mei'});
      final code = await friendService.ensureMyCode('owner');

      await tester.pumpWidget(
        MaterialApp(
          home: JoinByCodePage(
            groupService: groupService,
            auth: auth,
            vibrationService: vibration,
            friendService: friendService,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(JoinCodeKeys.codeField),
        FriendInvite.linkFor(code),
      );
      await tester.tap(find.byKey(JoinCodeKeys.findButton));
      await tester.pumpAndSettle();

      expect(find.byKey(FriendCodeKeys.previewCard), findsOneWidget);
      expect(find.text('Add Mei as a friend'), findsOneWidget);
    });
  });
}

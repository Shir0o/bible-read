import 'package:bible_read/pages/friend_invite_page.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/widgets/friend_code_keys.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stub_vibration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const code = '7QK4M2PX';

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late StubVibrationService vibration;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'me', displayName: 'Me'),
      signedIn: true,
    );
    vibration = StubVibrationService();
    await firestore.collection('friendCodes').doc(code).set({
      'ownerUid': 'tony',
    });
    await firestore.collection('users').doc('tony').set({'name': 'Tony'});
  });

  Future<void> openInvite(
    WidgetTester tester,
    FriendService friendService,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FriendInvitePage(
                      code: code,
                      auth: auth,
                      friendService: friendService,
                      vibrationService: vibration,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('names the inviter and offers to add them', (tester) async {
    await openInvite(tester, FriendService(firestore: firestore));

    expect(find.text('Tony invited you'), findsOneWidget);
    expect(find.byKey(FriendCodeKeys.inviteAddButton), findsOneWidget);
    expect(find.text('Add Tony as a friend'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(
      find.text('Either of you can unfriend at any time.'),
      findsOneWidget,
    );
  });

  testWidgets('"Not now" adds no one', (tester) async {
    var redeemCalls = 0;
    final service = FriendService(
      firestore: firestore,
      redeemFriendCodeFn: (_) async {
        redeemCalls++;
        return FriendRedemption.added;
      },
    );

    await openInvite(tester, service);
    await tester.tap(find.byKey(FriendCodeKeys.inviteNotNow));
    await tester.pumpAndSettle();

    expect(redeemCalls, 0);
    expect(find.byKey(FriendCodeKeys.inviteAddButton), findsNothing);
  });

  testWidgets('adding redeems the code once', (tester) async {
    var redeemCalls = 0;
    final service = FriendService(
      firestore: firestore,
      redeemFriendCodeFn: (_) async {
        redeemCalls++;
        return FriendRedemption.added;
      },
    );

    await openInvite(tester, service);
    await tester.tap(find.byKey(FriendCodeKeys.inviteAddButton));
    await tester.pumpAndSettle();

    expect(redeemCalls, 1);
    expect(find.text('You’re now friends with Tony'), findsOneWidget);
  });

  testWidgets('an unknown or reset code shows the no-longer-works screen',
      (tester) async {
    await firestore.collection('friendCodes').doc(code).delete();

    await openInvite(tester, FriendService(firestore: firestore));

    expect(find.text('This invite no longer works'), findsOneWidget);
    expect(find.byKey(FriendCodeKeys.inviteAddButton), findsNothing);
  });

  testWidgets('an invite from someone already a friend says so',
      (tester) async {
    await firestore
        .collection('users')
        .doc('me')
        .collection('friends')
        .doc('tony')
        .set({'uid': 'tony'});

    await openInvite(tester, FriendService(firestore: firestore));

    expect(find.text('You’re already friends with Tony.'), findsOneWidget);
    expect(find.byKey(FriendCodeKeys.inviteAddButton), findsNothing);
  });
}

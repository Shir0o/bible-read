import 'package:bible_read/main.dart';
import 'package:bible_read/pages/join_by_code_page.dart';
import 'package:bible_read/services/friend_invite.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  const code = '7QK4M2PX';
  const groupCode = 'ABC234';

  Future<IncomingLinkHandler> pumpShell(
    WidgetTester tester, {
    required bool signedIn,
    Widget Function(String code)? pageBuilder,
  }) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final handler = IncomingLinkHandler(
      auth: MockFirebaseAuth(
        mockUser: MockUser(uid: 'me', displayName: 'Me'),
        signedIn: signedIn,
      ),
      navigatorKey: navigatorKey,
      pageBuilder: pageBuilder ??
          (inviteCode) => Scaffold(body: Text('invite $inviteCode')),
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('home')),
      ),
    );
    return handler;
  }

  testWidgets('an incoming invite link opens the confirm screen',
      (tester) async {
    final handler = await pumpShell(tester, signedIn: true);

    await handler.handleUri(Uri.parse(FriendInvite.linkFor(code)));
    await tester.pumpAndSettle();

    expect(find.text('invite $code'), findsOneWidget);
  });

  testWidgets('an incoming group invite link opens the confirm screen',
      (tester) async {
    final handler = await pumpShell(tester, signedIn: true);

    await handler.handleUri(Uri.parse(FriendInvite.linkFor(groupCode)));
    await tester.pumpAndSettle();

    expect(find.text('invite $groupCode'), findsOneWidget);
  });

  testWidgets('a link that is not an invite is ignored', (tester) async {
    final handler = await pumpShell(tester, signedIn: true);

    await handler.handleUri(Uri.parse('https://example.com/hello'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a link that arrives signed out is held until sign-in',
      (tester) async {
    final handler = await pumpShell(tester, signedIn: false);

    await handler.handleUri(Uri.parse(FriendInvite.linkFor(code)));
    await tester.pumpAndSettle();
    expect(find.text('invite $code'), findsNothing);

    handler.onSignedIn();
    await tester.pumpAndSettle();
    expect(find.text('invite $code'), findsOneWidget);
  });

  testWidgets('default builder routes group code to JoinByCodePage',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final handler = IncomingLinkHandler(
      auth: MockFirebaseAuth(
        mockUser: MockUser(uid: 'me', displayName: 'Me'),
        signedIn: true,
      ),
      navigatorKey: navigatorKey,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('home')),
      ),
    );

    await handler.handleUri(Uri.parse(FriendInvite.linkFor(groupCode)));
    await tester.pumpAndSettle();

    expect(find.byType(JoinByCodePage), findsOneWidget);
  });
}

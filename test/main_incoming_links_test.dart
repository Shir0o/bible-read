import 'package:bible_read/main.dart';
import 'package:bible_read/services/friend_invite.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const code = '7QK4M2PX';

  Future<IncomingLinkHandler> pumpShell(
    WidgetTester tester, {
    required bool signedIn,
  }) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final handler = IncomingLinkHandler(
      auth: MockFirebaseAuth(
        mockUser: MockUser(uid: 'me', displayName: 'Me'),
        signedIn: signedIn,
      ),
      navigatorKey: navigatorKey,
      pageBuilder: (inviteCode) => Scaffold(body: Text('invite $inviteCode')),
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
}

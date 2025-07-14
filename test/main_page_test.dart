import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';

import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/read_log_page.dart';
import 'package:bible_read/widgets/responsive_scaffold.dart';

class FakeGoogleSignInPlatform extends GoogleSignInPlatform
    with MockPlatformInterfaceMixin {
  GoogleSignInUserData? user;
  int silentSignInCount = 0;

  @override
  Future<void> init({
    List<String> scopes = const <String>[],
    SignInOption signInOption = SignInOption.standard,
    String? hostedDomain,
    String? clientId,
  }) async {}

  @override
  Future<GoogleSignInUserData?> signInSilently() async {
    silentSignInCount++;
    return user;
  }

  @override
  Future<GoogleSignInUserData?> signIn() async => user;

  @override
  Future<GoogleSignInTokenData> getTokens({
    required String email,
    bool? shouldRecoverAuth,
  }) async {
    return GoogleSignInTokenData(
      idToken: 'idToken',
      accessToken: 'accessToken',
    );
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> isSignedIn() async => user != null;

  @override
  Future<void> clearAuthCache({required String token}) async {}

  @override
  Future<bool> requestScopes(List<String> scopes) async => true;

  @override
  Future<bool> canAccessScopes(
    List<String> scopes, {
    String? accessToken,
  }) async =>
      true;

  @override
  Stream<GoogleSignInUserData?>? get userDataEvents => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  late FakeGoogleSignInPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = fakePlatform;
  });

  testWidgets('MainPage navigation to profile', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: MainPage()));
    await tester.pumpAndSettle();

    // Profile should be shown by default when not authenticated
    expect(find.text('Sign in with Google'), findsOneWidget);

    // Profile should be shown when tapping profile or if it's the only page.
    if (find.byIcon(Icons.person).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.person));
      await tester.pumpAndSettle();
    }
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('navigation updates selected index', (tester) async {
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await tester.pumpWidget(MaterialApp(home: MainPage(auth: auth)));
    await tester.tap(find.text('Feed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ReadLogPage), findsOneWidget);
  });

  testWidgets('attemptSilentSignIn runs during initState', (tester) async {
    fakePlatform.user = GoogleSignInUserData(
      email: 'test@example.com',
      id: '123',
      displayName: 'Test',
    );
    await tester.pumpWidget(MaterialApp(home: MainPage()));
    await tester.pumpAndSettle();
    expect(fakePlatform.silentSignInCount, 1);
  });

  testWidgets('responsive scaffold switches layout', (tester) async {
    final auth =
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1'));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(800, 600)),
          child: MainPage(auth: auth),
        ),
      ),
    );
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(400, 600)),
          child: MainPage(auth: auth),
        ),
      ),
    );
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('unauthenticated navigation restricted to profile', (
    tester,
  ) async {
    final auth = MockFirebaseAuth();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 600)),
          child: MainPage(auth: auth),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDestination), findsNothing);
    expect(find.text('Sign in with Google'), findsOneWidget);

    final scaffold = tester.widget<ResponsiveScaffold>(
      find.byType(ResponsiveScaffold),
    );

    scaffold.onDestinationSelected(1);
    await tester.pump();

    expect(find.text('Sign in with Google'), findsOneWidget);
  });
}

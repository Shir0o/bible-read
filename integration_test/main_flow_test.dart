import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/services/google_sign_in_factory.dart';

class FakeGoogleSignInPlatform extends GoogleSignInPlatform
    with MockPlatformInterfaceMixin {
  GoogleSignInUserData? user;

  @override
  Future<void> init({
    List<String> scopes = const <String>[],
    SignInOption signInOption = SignInOption.standard,
    String? hostedDomain,
    String? clientId,
  }) async {}

  @override
  Future<GoogleSignInUserData?> signInSilently() async => user;

  @override
  Future<GoogleSignInUserData?> signIn() async => user;

  @override
  Future<GoogleSignInTokenData> getTokens({
    required String email,
    bool? shouldRecoverAuth,
  }) async {
    return GoogleSignInTokenData(
      idToken: 'id',
      accessToken: 'access',
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
  Future<bool> canAccessScopes(List<String> scopes,
          {String? accessToken}) async =>
      true;

  @override
  Stream<GoogleSignInUserData?>? get userDataEvents => null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('navigate between pages', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    final google = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = google;

    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          firestore: firestore,
          auth: auth,
          googleSignInProvider: createGoogleSignIn,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify HomePage is showing Today's Reading (or Daily Reading if no plan)
    expect(find.textContaining('Reading'), findsAtLeast(1));

    // Tap Community tab
    await tester.tap(find.byIcon(Icons.people_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Friends Activity'), findsOneWidget);

    // Tap Journey tab
    await tester.tap(find.byIcon(Icons.map_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Reading Journey'), findsOneWidget);

    // Tap Home tab
    await tester.tap(find.byIcon(Icons.home));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);

    // Open Menu via Profile Avatar on Community page (since HomePage might not have a direct menu button in this setup)
    await tester.tap(find.byIcon(Icons.people_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Open menu'));
    await tester.pumpAndSettle();

    // Verify some menu items
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Challenges'), findsOneWidget);
    expect(find.text('Friends'), findsOneWidget);

    // Tap Friends in menu
    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();
    expect(find.text('Friends'), findsAtLeast(1));
  });
}

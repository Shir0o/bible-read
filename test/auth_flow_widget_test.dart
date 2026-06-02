import 'package:bible_read/main.dart';
import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/pages/login_page.dart';
import 'package:bible_read/pages/signup_page.dart';
import 'package:bible_read/pages/welcome_page.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockGoogleSignInPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements GoogleSignInPlatform {}

class FakeInitParameters extends Fake implements InitParameters {}

class FakeAttemptLightweightAuthenticationParameters extends Fake
    implements AttemptLightweightAuthenticationParameters {}

class FakeSignOutParams extends Fake implements SignOutParams {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  late MockGoogleSignInPlatform mockGoogleSignInPlatform;

  setUpAll(() async {
    await Firebase.initializeApp();
    registerFallbackValue(FakeInitParameters());
    registerFallbackValue(FakeAttemptLightweightAuthenticationParameters());
    registerFallbackValue(FakeSignOutParams());
  });

  setUp(() {
    mockGoogleSignInPlatform = MockGoogleSignInPlatform();
    GoogleSignInPlatform.instance = mockGoogleSignInPlatform;
    when(() => mockGoogleSignInPlatform.init(any())).thenAnswer((_) async {});
    when(
      () => mockGoogleSignInPlatform.attemptLightweightAuthentication(any()),
    ).thenAnswer((_) async => null);
    when(
      () => mockGoogleSignInPlatform.signOut(any()),
    ).thenAnswer((_) async {});
    when(
      () => mockGoogleSignInPlatform.authenticationEvents,
    ).thenAnswer((_) => const Stream.empty());
  });

  testWidgets('Comprehensive Auth Flow Test', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth();

    // Start the app
    await tester.pumpWidget(
      MyApp(appCheckFailed: false, firestore: firestore, auth: auth),
    );
    await tester.pumpAndSettle();

    // 1. Verify WelcomePage is shown
    expect(find.byType(WelcomePage), findsOneWidget);

    // 2. Navigate to AuthSelectionPage
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(find.text('Join the Community'), findsOneWidget);

    // 3. Navigate to SignupPage
    await tester.tap(find.text('Sign up with email'));
    await tester.pumpAndSettle();
    expect(find.byType(SignupPage), findsOneWidget);

    // 4. Test Signup Validation
    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(find.text('Please fill in all fields'), findsAtLeast(1));

    // 5. Fill Signup Form
    await tester.enterText(find.byType(TextFormField).at(0), 'Test User');
    await tester.enterText(
      find.byKey(const Key('signupEmailField')),
      'test@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('signupPasswordField')),
      'password123',
    );

    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    // Succession animation takes some time, pump multiple times or use a longer settle
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // 6. Verify we are logged in and on HomePage
    expect(find.byType(HomePage), findsOneWidget);
    expect(auth.currentUser, isNotNull);
    expect(auth.currentUser!.displayName, 'Test User');

    // 6b. Verify Firestore data
    final userDoc =
        await firestore.collection('users').doc(auth.currentUser!.uid).get();
    expect(userDoc.exists, isTrue);
    expect(userDoc.data()?['name'], 'Test User');
    expect(userDoc.data()?['email'], 'test@example.com');

    // 7. Sign Out
    // Navigate to Community page where the profile icon (menu) is visible
    await tester.tap(find.byIcon(Icons.people_outlined));
    await tester.pumpAndSettle();

    final menuButton = find.bySemanticsLabel('Open menu');
    await tester.tap(menuButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    // 8. Verify we are back to WelcomePage
    expect(find.byType(WelcomePage), findsOneWidget);
    expect(auth.currentUser, isNull);

    // 9. Navigate to LoginPage
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);

    // 10. Test Login Validation
    final loginButton = find.widgetWithText(ElevatedButton, 'Login');
    await tester.ensureVisible(loginButton);
    await tester.tap(loginButton);
    await tester.pumpAndSettle();
    expect(find.text('Please fill in all fields'), findsAtLeast(1));

    // 12. Login with correct credentials
    await tester.enterText(
      find.byKey(const Key('loginEmailField')),
      'test@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('loginPasswordField')),
      'password123',
    );
    await tester.ensureVisible(loginButton);
    await tester.tap(loginButton);
    await tester.pumpAndSettle();

    // 13. Verify we are logged in again
    expect(find.byType(HomePage), findsOneWidget);
    expect(auth.currentUser, isNotNull);
    expect(auth.currentUser!.email, 'test@example.com');
  });
}

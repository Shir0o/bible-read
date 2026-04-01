import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:bible_read/pages/signup_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';
import 'dart:async';

class MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return MockHttpClient();
  }
}

class MockHttpClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return MockHttpClientRequest();
  }
}

class MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async {
    return MockHttpClientResponse();
  }
}

class MockHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  int get contentLength => 0;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.empty().listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

class RecordingAuth extends MockFirebaseAuth {
  bool createCalled = false;
  String? email;
  String? password;

  RecordingAuth({super.mockUser}) : super();

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    createCalled = true;
    this.email = email;
    this.password = password;
    return super.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }
}

class MockVibrationService extends VibrationService {
  MockVibrationService() : super();

  @override
  Future<void> lightImpact() async {}

  @override
  Future<void> mediumImpact() async {}
}

class FakeFirebaseMessaging extends Fake implements FirebaseMessaging {
  @override
  Future<String?> getToken({String? vapidKey}) async => 'fake_token';
}

class FakeGoogleSignIn extends Fake implements GoogleSignIn {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MockHttpOverrides();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('SignupPage creates account, writes user doc and navigates', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final auth = RecordingAuth();
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: SignupPage(
          auth: auth,
          firestore: firestore,
          vibrationService: MockVibrationService(),
          googleSignInProvider: () => FakeGoogleSignIn(),
          mainPageBuilder: (_) => MainPage(
            auth: auth, // Pass same auth so it sees logged in user
            firestore: firestore,
            messaging: FakeFirebaseMessaging(),
            vibrationService: MockVibrationService(),
          ),
        ),
      ),
    );

    // Enter Full Name
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full Name'),
      'Test User',
    );

    // Enter Email
    await tester.enterText(
      find.byKey(const Key('signupEmailField')),
      'user@example.com',
    );

    // Enter Password
    await tester.enterText(find.byKey(const Key('signupPasswordField')), 'password');

    // Tap Create Account
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
    await tester.pumpAndSettle();

    expect(auth.createCalled, isTrue);
    expect(auth.email, 'user@example.com');
    expect(auth.password, 'password');

    final uid = auth.currentUser!.uid;
    final doc = await firestore.collection('users').doc(uid).get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['name'], 'Test User');
    expect(doc.data()!['email'], 'user@example.com');

    // Check if display name was updated
    expect(auth.currentUser!.displayName, 'Test User');

    expect(find.byType(MainPage), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('SignupPage shows validation errors for empty fields',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SignupPage(
          auth: RecordingAuth(),
          firestore: FakeFirebaseFirestore(),
          vibrationService: MockVibrationService(),
          googleSignInProvider: () => FakeGoogleSignIn(),
        ),
      ),
    );

    // Tap Create Account without entering anything
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
    await tester.pump();

    expect(find.text('Please fill in all fields'), findsAtLeast(3));
  });

  testWidgets('SignupPage shows error for invalid email', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SignupPage(
          auth: RecordingAuth(),
          firestore: FakeFirebaseFirestore(),
          vibrationService: MockVibrationService(),
          googleSignInProvider: () => FakeGoogleSignIn(),
        ),
      ),
    );

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Full Name'), 'Test User');
    await tester.enterText(
        find.byKey(const Key('signupEmailField')), 'invalid-email');
    await tester.enterText(find.byKey(const Key('signupPasswordField')), 'password');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
    await tester.pump();

    expect(find.text('Please enter a valid email address'), findsOneWidget);
  });

  testWidgets('SignupPage shows error for short password', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SignupPage(
          auth: RecordingAuth(),
          firestore: FakeFirebaseFirestore(),
          vibrationService: MockVibrationService(),
          googleSignInProvider: () => FakeGoogleSignIn(),
        ),
      ),
    );

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Full Name'), 'Test User');
    await tester.enterText(
        find.byKey(const Key('signupEmailField')), 'user@example.com');
    await tester.enterText(find.byKey(const Key('signupPasswordField')), '12345');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
    await tester.pump();

    expect(find.text('Password must be at least 6 characters'), findsOneWidget);
  });

  testWidgets('Social button has correct semantics and tooltip',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SignupPage(
          auth: RecordingAuth(),
          firestore: FakeFirebaseFirestore(),
          vibrationService: MockVibrationService(),
          googleSignInProvider: () => FakeGoogleSignIn(),
        ),
      ),
    );

    // Verify Tooltip matches label
    expect(find.byTooltip('Sign in with Google'), findsOneWidget);

    // Verify Semantics
    // We look for a Semantics widget with the specific label
    final semanticHandle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Sign in with Google'), findsOneWidget);
    semanticHandle.dispose();
  });

  testWidgets('Terms and Privacy links have tap recognizers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SignupPage(
          auth: RecordingAuth(),
          firestore: FakeFirebaseFirestore(),
          vibrationService: MockVibrationService(),
          googleSignInProvider: () => FakeGoogleSignIn(),
        ),
      ),
    );

    // Find the RichText widget that contains "Terms of Service" and "Privacy Policy"
    final richTextFinder = find.byWidgetPredicate((widget) {
      if (widget is RichText && widget.text is TextSpan) {
        final span = widget.text as TextSpan;
        final children = span.children;
        if (children == null) return false;

        bool hasTerms =
            children.any((c) => c is TextSpan && c.text == 'Terms of Service');
        bool hasPrivacy =
            children.any((c) => c is TextSpan && c.text == 'Privacy Policy');
        return hasTerms && hasPrivacy;
      }
      return false;
    });

    expect(richTextFinder, findsOneWidget);

    final richText = tester.widget<RichText>(richTextFinder);
    final textSpan = richText.text as TextSpan;

    final termsSpan = textSpan.children!
            .firstWhere((c) => (c as TextSpan).text == 'Terms of Service')
        as TextSpan;
    expect(termsSpan.recognizer, isNotNull);
    expect(termsSpan.recognizer, isA<TapGestureRecognizer>());

    final privacySpan = textSpan.children!
            .firstWhere((c) => (c as TextSpan).text == 'Privacy Policy')
        as TextSpan;
    expect(privacySpan.recognizer, isNotNull);
    expect(privacySpan.recognizer, isA<TapGestureRecognizer>());
  });

  testWidgets('Log in link has correct semantics and tooltip', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SignupPage(
          auth: RecordingAuth(),
          firestore: FakeFirebaseFirestore(),
          vibrationService: MockVibrationService(),
          googleSignInProvider: () => FakeGoogleSignIn(),
        ),
      ),
    );

    // Scroll to the bottom to ensure the link is visible
    final loginTextFinder = find.text('Log in');

    // Ensure it is visible by scrolling
    await tester.dragUntilVisible(
      loginTextFinder,
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    // Verify Semantics
    final semanticsHandle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(const Key('loginLinkSemantics'))),
      matchesSemantics(
        label: 'Log in',
        isButton: true,
      ),
    );
    semanticsHandle.dispose();

    // Verify Tooltip
    expect(find.byTooltip('Log in'), findsOneWidget);
  });
}

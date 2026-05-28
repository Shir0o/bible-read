import 'package:bible_read/pages/auth_selection_page.dart';
import 'package:bible_read/pages/login_page.dart';
import 'package:bible_read/pages/signup_page.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import '../helpers/fake_google_sign_in_platform.dart';

class MockVibrationService extends VibrationService {
  int lightImpactCount = 0;
  @override
  Future<void> lightImpact() async {
    lightImpactCount++;
  }
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

  testWidgets('AuthSelectionPage renders correctly', (tester) async {
    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: AuthSelectionPage(
            auth: MockFirebaseAuth(),
            firestore: FakeFirebaseFirestore(),
            googleSignInProvider: () => GoogleSignIn.instance,
            vibrationService: MockVibrationService(),
          ),
        ),
      );

      expect(find.text('Join the Community'), findsOneWidget);
      expect(
        find.text(
          'Sign up to track your progress and connect with your reading group.',
        ),
        findsOneWidget,
      );
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Sign up with email'), findsOneWidget);
      expect(find.text('Log in'), findsOneWidget);
    });
  });

  testWidgets('Navigates to SignupPage', (tester) async {
    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: AuthSelectionPage(
            auth: MockFirebaseAuth(),
            firestore: FakeFirebaseFirestore(),
            googleSignInProvider: () => GoogleSignIn.instance,
            vibrationService: MockVibrationService(),
          ),
        ),
      );

      await tester.tap(find.text('Sign up with email'));
      await tester.pumpAndSettle();
      expect(find.byType(SignupPage), findsOneWidget);
    });
  });

  testWidgets('Navigates to LoginPage', (tester) async {
    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: AuthSelectionPage(
            auth: MockFirebaseAuth(),
            firestore: FakeFirebaseFirestore(),
            googleSignInProvider: () => GoogleSignIn.instance,
            vibrationService: MockVibrationService(),
          ),
        ),
      );

      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
    });
  });
}

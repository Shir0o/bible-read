import 'package:bible_read/pages/auth_selection_page.dart';
import 'package:bible_read/pages/login_page.dart';
import 'package:bible_read/pages/settings_page.dart';
import 'package:bible_read/services/apple_sign_in_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/widgets/auth/apple_sign_in_button.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_google_sign_in_platform.dart';

class MockAppleSignInService implements AppleSignInService {
  @override
  bool isSupported;
  bool signInCalled = false;
  UserCredential? returnCredential;
  Exception? errorToThrow;

  MockAppleSignInService({
    this.isSupported = true,
    this.returnCredential,
    this.errorToThrow,
  });

  @override
  Future<UserCredential?> signIn() async {
    signInCalled = true;
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return returnCredential;
  }
}

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

  setUp(() {
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();
    SharedPreferences.setMockInitialValues({});
  });

  group('AppleSignInButton visibility and action tests', () {
    testWidgets(
      'renders AppleSignInButton on AuthSelectionPage when supported and triggers signIn',
      (tester) async {
        final mockApple = MockAppleSignInService(isSupported: true);
        final mockVibration = MockVibrationService();

        await mockNetworkImagesFor(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: AuthSelectionPage(
                auth: MockFirebaseAuth(),
                firestore: FakeFirebaseFirestore(),
                googleSignInProvider: () => GoogleSignIn.instance,
                appleSignInService: mockApple,
                vibrationService: mockVibration,
              ),
            ),
          );

          expect(find.byType(AppleSignInButton), findsOneWidget);
          expect(find.byKey(const Key('appleSignInButton')), findsOneWidget);

          await tester.tap(find.byKey(const Key('appleSignInButton')));
          await tester.pumpAndSettle();

          expect(mockApple.signInCalled, isTrue);
          expect(mockVibration.lightImpactCount, equals(1));
        });
      },
    );

    testWidgets(
      'does not render AppleSignInButton on AuthSelectionPage when unsupported',
      (tester) async {
        final mockApple = MockAppleSignInService(isSupported: false);

        await mockNetworkImagesFor(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: AuthSelectionPage(
                auth: MockFirebaseAuth(),
                firestore: FakeFirebaseFirestore(),
                googleSignInProvider: () => GoogleSignIn.instance,
                appleSignInService: mockApple,
              ),
            ),
          );

          expect(find.byKey(const Key('appleSignInButton')), findsNothing);
        });
      },
    );

    testWidgets(
      'renders AppleSignInButton on LoginPage when supported and triggers signIn',
      (tester) async {
        final mockApple = MockAppleSignInService(isSupported: true);
        final mockVibration = MockVibrationService();

        await mockNetworkImagesFor(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: LoginPage(
                auth: MockFirebaseAuth(),
                firestore: FakeFirebaseFirestore(),
                googleSignInProvider: () => GoogleSignIn.instance,
                appleSignInService: mockApple,
                vibrationService: mockVibration,
              ),
            ),
          );

          expect(find.byType(AppleSignInButton), findsOneWidget);
          expect(find.byKey(const Key('appleSignInButton')), findsOneWidget);

          final appleBtn = find.byKey(const Key('appleSignInButton'));
          await tester.ensureVisible(appleBtn);
          await tester.tap(appleBtn);
          await tester.pumpAndSettle();

          expect(mockApple.signInCalled, isTrue);
          expect(mockVibration.lightImpactCount, equals(1));
        });
      },
    );

    testWidgets(
      'renders AppleSignInButton on SettingsPage when unauthenticated and supported',
      (tester) async {
        final mockApple = MockAppleSignInService(isSupported: true);

        await mockNetworkImagesFor(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: SettingsPage(
                auth: MockFirebaseAuth(), // currentUser is null
                firestore: FakeFirebaseFirestore(),
                googleSignInProvider: () => GoogleSignIn.instance,
                appleSignInService: mockApple,
              ),
            ),
          );

          expect(find.byType(AppleSignInButton), findsOneWidget);
          expect(find.byKey(const Key('appleSignInButton')), findsOneWidget);

          await tester.tap(find.byKey(const Key('appleSignInButton')));
          await tester.pumpAndSettle();

          expect(mockApple.signInCalled, isTrue);
        });
      },
    );

    testWidgets(
      'does not render AppleSignInButton on SettingsPage when unsupported',
      (tester) async {
        final mockApple = MockAppleSignInService(isSupported: false);

        await mockNetworkImagesFor(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: SettingsPage(
                auth: MockFirebaseAuth(),
                firestore: FakeFirebaseFirestore(),
                googleSignInProvider: () => GoogleSignIn.instance,
                appleSignInService: mockApple,
              ),
            ),
          );

          expect(find.byKey(const Key('appleSignInButton')), findsNothing);
        });
      },
    );
  });
}

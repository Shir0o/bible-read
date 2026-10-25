import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/pages/login_page.dart';
import 'package:bible_read/services/apple_sign_in_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:google_sign_in_mocks/google_sign_in_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import '../helpers/path_provider_mock.dart';
import '../helpers/pump_golden.dart';
import '../helpers/mock_sqflite.dart';
import '../helpers/mocks.dart';
import 'package:mocktail/mocktail.dart';

/// Reports Apple Sign-In as supported so the golden shows the iOS layout
/// whatever host renders it (the real service checks `Platform.isIOS`).
class _SupportedAppleSignInService implements AppleSignInService {
  @override
  bool get isSupported => true;

  @override
  Future<UserCredential?> signIn() async => null;

  @override
  Future<AuthCredential?> getCredential() async => null;
}

void main() {
  setupPathProviderMocks();
  setupSqfliteMock();

  testWidgets('LoginPage Golden Test', (tester) async {
    final auth = MockFirebaseAuth();
    final cacheManager = MockCacheManager();

    // Stub cacheManager to avoid errors during widget construction
    when(
      () => cacheManager.getFileStream(
        any(),
        key: any(named: 'key'),
        headers: any(named: 'headers'),
        withProgress: any(named: 'withProgress'),
      ),
    ).thenAnswer((_) => const Stream.empty());

    await tester.pumpGolden(
      LoginPage(
        auth: auth,
        firestore: FakeFirebaseFirestore(),
        googleSignInProvider: () => MockGoogleSignIn(),
        cacheManager: cacheManager,
        appleSignInService: _SupportedAppleSignInService(),
      ),
      brightness: Brightness.light,
    );

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(LoginPage),
      matchesGoldenFile('goldens/login_page.png'),
    );
  });
}

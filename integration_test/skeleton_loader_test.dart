import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/services/google_sign_in_factory.dart';
import 'package:bible_read/widgets/app_header.dart';
import 'package:bible_read/widgets/skeletons/home_page_skeleton.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('Skeleton Loader persistence and header visibility', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final mockUser = MockUser(
      uid: 'u1',
      displayName: 'Test User',
      email: 'test@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

    // Seed data
    await firestore.collection('users').doc('u1').set({
      'displayName': 'Test User',
      'email': 'test@example.com',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          firestore: firestore,
          auth: auth,
          googleSignInProvider: createGoogleSignIn,
        ),
      ),
    );

    // 1. Verify Skeleton is visible immediately after first pump
    await tester.pump();
    expect(find.byType(HomePageSkeleton), findsOneWidget);
    
    // MANDATE: Verify Page Title/Header is visible while skeleton is showing
    // AppHeader contains the Bible Read title or greeting.
    expect(find.byType(AppHeader), findsOneWidget);

    // 2. Verify Skeleton persists for some time (e.g., 500ms)
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(HomePageSkeleton), findsOneWidget);
    expect(find.text('Yes, I read'), findsNothing);

    // 3. Verify Skeleton is still there at 900ms (just before minTime 1000ms)
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(HomePageSkeleton), findsOneWidget);

    // 4. Verify Skeleton is replaced by content after minTime (1000ms) + switchDuration (300ms)
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    
    expect(find.byType(HomePageSkeleton), findsNothing);
    expect(find.text('Yes, I read'), findsOneWidget);
    
    // Header should still be there
    expect(find.byType(AppHeader), findsOneWidget);
  });
}

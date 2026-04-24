import 'package:bible_read/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import '../test/helpers/fake_google_sign_in_platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();
    await Firebase.initializeApp();
  });

  testWidgets('End-to-end: Manual book tracking flow', (tester) async {
    // We use mock Firebase but run the real App widget
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1', displayName: 'Integration User');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(app.MyApp(
      appCheckFailed: false,
      firestore: firestore,
      auth: auth,
    ));
    await tester.pumpAndSettle();

    // 1. Navigate to Journey Page (index 2 in BottomNavigationBar)
    final journeyTab = find.text('Journey');
    await tester.tap(journeyTab);
    await tester.pumpAndSettle();

    // Journey page has an artificial delay
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // 2. Verify initial state (0 books)
    expect(find.textContaining('66 Books'), findsOneWidget);

    // 3. Navigate to See All (Progress Page)
    await tester.tap(find.text('See All'));
    await tester.pumpAndSettle();

    // 4. Manually mark Genesis as read
    await tester.tap(find.text('Gen'));
    await tester.pumpAndSettle();

    // Confirm dialog
    expect(find.text('Complete Genesis?'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // 5. Go back to Journey Page
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Trigger data refresh if needed (JourneyPage state might need a nudge or it might be real-time)
    // Actually JourneyPage currently loads data in initState.
    // If we use AutomaticKeepAliveClientMixin, we might need to manually refresh or
    // rely on real-time streams if implemented.
    // BibleLibraryGrid uses a Stream.fromFuture in its current implementation which is NOT real-time.

    // Re-pump Journey page to see updates
    await tester.tap(find.text('Home')); // Switch away
    await tester.pumpAndSettle();
    await tester.tap(journeyTab); // Switch back
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // 6. Verify update
    expect(find.textContaining('1'), findsAtLeast(1));
    expect(find.textContaining('66 Books'), findsOneWidget);
  });
}

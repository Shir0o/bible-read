import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/services/google_sign_in_factory.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('Group Creation Flow', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final mockUser = MockUser(
      uid: 'u1',
      displayName: 'Test User',
      email: 'test@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          firestore: firestore,
          auth: auth,
          googleSignInProvider: createGoogleSignIn,
        ),
      ),
    );

    // 1. Wait for initial load
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    // 2. Navigate to Community Page
    await tester.tap(find.byIcon(Icons.people_outlined));
    await tester.pumpAndSettle();

    // 3. Tap "View All" in Group Progress section
    await tester.tap(find.text('View All').first);
    await tester.pumpAndSettle();

    // 4. Tap "Join or Create Group" bottom button
    await tester.tap(find.text('Join or Create Group'));
    await tester.pumpAndSettle();

    // 5. Tap "Create New Group" in bottom sheet
    await tester.tap(find.text('Create New Group'));
    await tester.pumpAndSettle();

    // 6. Search and add "Genesis"
    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'Genesis');
    await tester.pump(const Duration(milliseconds: 500));
    
    // Tap the Genesis option in the list
    await tester.tap(find.text('Genesis').last);
    await tester.pumpAndSettle();

    // 7. Select End Date
    final dateField = find.text('mm/dd/yyyy');
    await tester.ensureVisible(dateField);
    await tester.pumpAndSettle();
    await tester.tap(dateField);
    await tester.pumpAndSettle();
    
    final okButton = find.text('OK');
    if (tester.any(okButton)) {
      await tester.tap(okButton);
    } else {
      await tester.tap(find.byType(TextButton).last);
    }
    await tester.pumpAndSettle();

    // 8. Tap "Create Schedule"
    await tester.tap(find.text('Create Schedule'));
    
    // Avoid pumpAndSettle if it times out, use multiple pumps
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pumpAndSettle();

    // 9. Verify navigation to GroupDetailPage
    expect(find.text('Genesis Plan'), findsWidgets);
    expect(find.text('Members'), findsWidgets);
    expect(find.text('1 Members'), findsWidgets);
  });
}

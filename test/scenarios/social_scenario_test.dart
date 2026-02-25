import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/friends_page.dart';
import 'package:google_sign_in_mocks/google_sign_in_mocks.dart';
import '../helpers/pump_app.dart';
import '../helpers/firebase_seeder.dart';
import '../helpers/mocks.dart';
import '../helpers/stub_vibration_service.dart';

void main() {
  testWidgets('Social Scenario: User navigates to Friends and sends a request',
      (tester) async {
    final auth = MockFirebaseAuth(signedIn: true);
    final firestore = FakeFirebaseFirestore();
    final messaging = MockFirebaseMessaging();
    final vibration = StubVibrationService();
    final seeder = FirebaseSeeder(firestore);
    final currentUser = auth.currentUser!;

    // Seed current user
    await seeder.seedUser(uid: currentUser.uid, name: 'Alice');

    // Seed another user to add
    await seeder.seedUser(uid: 'bob_uid', name: 'Bob', email: 'bob@example.com');

    await tester.pumpApp(
      MainPage(
        auth: auth,
        firestore: firestore,
        messaging: messaging,
        vibrationService: vibration,
        googleSignInProvider: () => MockGoogleSignIn(),
      ),
    );
    await tester.pumpAndSettle();

    // Open Menu (assuming standard hamburger icon)
    // If ResponsiveScaffold uses a specific icon or key, we might need to adjust.
    // Usually Icons.menu.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    // Tap "Friends" in menu
    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();

    // Should be on FriendsPage
    expect(find.byType(FriendsPage), findsOneWidget);

    // Tap "Add Friend" button (FAB or Action)
    // FriendsPage usually has an action to add friends.
    // Let's assume there is an icon or button.
    // Common pattern: FAB with person_add or AppBar action.
    final addBtn = find.byIcon(Icons.person_add);
    if (addBtn.evaluate().isNotEmpty) {
      await tester.tap(addBtn);
    } else {
      // Maybe text "Add Friend"?
       await tester.tap(find.text('Add Friend'));
    }
    await tester.pumpAndSettle();

    // Should be on AddFriendPage (or dialog)
    // Verify TextField exists
    expect(find.byType(TextField), findsOneWidget);

    // Enter email "bob@example.com"
    await tester.enterText(find.byType(TextField), 'bob@example.com');
    await tester.pump();

    // Tap Send (Button text might be "Send Request" or "Add")
    // Use generic search if unsure
    final sendBtn = find.text('Send Request');
    if (sendBtn.evaluate().isNotEmpty) {
        await tester.tap(sendBtn);
    } else {
        await tester.tap(find.text('Add'));
    }
    await tester.pumpAndSettle();

    // Verify success via SnackBar or text
    // "Friend request sent!" or similar.
    expect(find.textContaining('sent'), findsOneWidget);

    // Verify Firestore
    final requests = await firestore.collection('users').doc('bob_uid').collection('friend_requests').get();
    expect(requests.docs.length, 1);
    expect(requests.docs.first.data()['fromUid'], currentUser.uid);
  });
}

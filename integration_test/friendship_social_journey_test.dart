import 'package:bible_read/models/notification_preferences.dart';
import 'package:bible_read/pages/add_friend_page.dart';
import 'package:bible_read/pages/friend_requests_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('Friendship & Social Connectivity Journey', (tester) async {
    final firestore = FakeFirebaseFirestore();
    
    // 1. Setup Mock Users
    // Current user (Alice)
    final mockCurrentUser = MockUser(
      uid: 'alice_uid',
      displayName: 'Alice',
      email: 'alice@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: mockCurrentUser, signedIn: true);
    
    // Potential friend (Bob)
    await firestore.collection('users').doc('bob_uid').set({
      'name': 'Bob',
      'email': 'bob@example.com',
    });

    final friendService = FriendService(
      firestore: firestore,
      acceptFriendRequestFn: ({
        required String fromUid,
        required String toUid,
        required String fromName,
        required String toName,
      }) async {
        // Simulate what the Cloud Function does
        final batch = firestore.batch();
        batch.set(firestore.collection('users').doc(fromUid).collection('friends').doc(toUid), {
          'name': toName,
          'timestamp': FieldValue.serverTimestamp(),
        });
        batch.set(firestore.collection('users').doc(toUid).collection('friends').doc(fromUid), {
          'name': fromName,
          'timestamp': FieldValue.serverTimestamp(),
        });
        await batch.commit();
      },
    );

    // 2. Launch App
    await tester.pumpWidget(MaterialApp(
      home: MainPage(
        firestore: firestore,
        auth: auth,
        friendService: friendService,
      ),
    ));
    await tester.pumpAndSettle();

    // Navigate to Friends via Side Menu (using AppHeader's profile icon)
    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle();

    final profileButton = find.byTooltip('Open menu');
    expect(profileButton, findsOneWidget);
    await tester.tap(profileButton);
    await tester.pumpAndSettle();

    final friendsMenuItem = find.text('Friends');
    expect(friendsMenuItem, findsOneWidget);
    await tester.tap(friendsMenuItem);
    await tester.pumpAndSettle();

    // 3. Verify Empty State and Navigate to Add Friend
    expect(find.text('No friends yet'), findsOneWidget);
    await tester.tap(find.text('Find Friends'));
    await tester.pumpAndSettle();

    // 4. Send Friend Request to Bob
    expect(find.byType(AddFriendPage), findsOneWidget);
    await tester.enterText(find.byKey(const Key('addFriendEmailField')), 'bob@example.com');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    // Verify request was written to Firestore
    final sentRequest = await firestore
        .collection('users')
        .doc('alice_uid')
        .collection('friendRequestsSent')
        .doc('bob_uid')
        .get();
    expect(sentRequest.exists, isTrue);

    // 5. Back to Friends Page
    expect(find.text('No friends yet'), findsOneWidget);

    // 6. Simulate Bob sending a request to Alice
    await firestore
        .collection('users')
        .doc('alice_uid')
        .collection('friendRequestsReceived')
        .doc('bob_uid')
        .set({
      'name': 'Bob',
      'timestamp': FieldValue.serverTimestamp(),
    });

    // 7. Open Friend Requests Page
    await tester.tap(find.byTooltip('Add friend').last);
    await tester.pumpAndSettle();
    expect(find.byType(FriendRequestsPage), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);

    // 8. Accept Bob's Request
    await tester.tap(find.byTooltip('Accept request'));
    await tester.pumpAndSettle();

    // 9. Verify Alice and Bob are now friends
    await tester.pageBack();
    await tester.pumpAndSettle();
    
    expect(find.text('Bob'), findsOneWidget);
    expect(find.byTooltip('Send encouragement'), findsOneWidget);
  });
}

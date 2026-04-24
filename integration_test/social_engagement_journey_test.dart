import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/widgets/feed_card.dart';
import 'package:bible_read/widgets/community/community_activity_item.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import '../test/helpers/fake_google_sign_in_platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  testWidgets('Social Feed & Engagement Journey', (tester) async {
    final google = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = google;

    final firestore = FakeFirebaseFirestore();
    final now = DateTime.now();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // 1. Setup Alice (current user)
    final alice = MockUser(
      uid: 'alice_uid',
      displayName: 'Alice',
      email: 'alice@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: alice, signedIn: true);

    // 2. Setup Bob (friend) and his activity
    await firestore.collection('users').doc('bob_uid').set({
      'name': 'Bob',
      'email': 'bob@example.com',
    });

    // Alice and Bob are friends
    await firestore
        .collection('users')
        .doc('alice_uid')
        .collection('friends')
        .doc('bob_uid')
        .set({
      'name': 'Bob',
      'timestamp': Timestamp.fromDate(now),
    });

    // Bob has read today
    await firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc('bob_uid')
        .set({
      'name': 'Bob',
      'uid': 'bob_uid',
      'timestamp': Timestamp.fromDate(now),
      'dateId': dateKey,
    });

    // 3. Launch App
    await tester.pumpWidget(MaterialApp(
      home: MainPage(
        firestore: firestore,
        auth: auth,
      ),
    ));
    await tester.pumpAndSettle();

    // 4. Navigate to Community tab
    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle();
    // Wait for SkeletonLoader (min 1000ms)
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // 5. Verify Bob's activity is visible in the feed
    expect(find.text('No recent activity.'), findsNothing);
    final activityItem = find.byType(CommunityActivityItem);
    if (tester.any(activityItem)) {
      debugPrint('Found activity item');
    } else {
      debugPrint('Activity item NOT found');
      debugDumpApp();
    }
    expect(find.textContaining('Bob', findRichText: true), findsAtLeast(1));
    expect(
        find.textContaining('completed', findRichText: true), findsOneWidget);

    // 6. Navigate to View All (ReadLogPage)
    final viewAllButton = find.text('View All').last;
    expect(viewAllButton, findsOneWidget);
    await tester.tap(viewAllButton);
    await tester.pumpAndSettle();

    // 7. Verify we are in ReadLogPage (Today's Readers)
    expect(find.text("Today's Readers"), findsOneWidget);
    // Wait for ReadLogView to load
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byType(FeedCard), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);

    // 8. Like Bob's post (Encourage)
    final encourageButton = find.text('Encourage');
    expect(encourageButton, findsOneWidget);
    await tester.tap(encourageButton);
    await tester.pumpAndSettle();

    // Verify Like is written to Firestore
    final likeDoc = await firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc('bob_uid')
        .collection('likes')
        .doc('alice_uid')
        .get();
    expect(likeDoc.exists, isTrue);

    // FeedCard shows names of likers
    expect(find.text('Alice'), findsOneWidget);

    // 9. Comment on Bob's post
    final commentButton = find.text('Comment');
    expect(commentButton, findsOneWidget);
    await tester.tap(commentButton);
    await tester.pumpAndSettle();

    // Enter comment
    final commentField = find.byType(TextField);
    expect(commentField, findsOneWidget);
    await tester.enterText(commentField, 'Great job Bob!');
    await tester.pumpAndSettle();

    // Send comment
    final sendButton = find.byTooltip('Send comment');
    expect(sendButton, findsOneWidget);
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    // 10. Verify comment appears in UI and Firestore
    expect(find.text('Great job Bob!'), findsOneWidget);
    expect(find.text('Alice:'), findsOneWidget);

    final commentsSnap = await firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc('bob_uid')
        .collection('comments')
        .get();
    expect(commentsSnap.docs.length, 1);
    expect(commentsSnap.docs.first.data()['message'], 'Great job Bob!');

    // 11. Go back to CommunityPage and verify updated state
    await tester.pageBack();
    await tester.pumpAndSettle();

    // CommunityPage uses CommunityActivityItem which shows "commented on" if comments exist
    expect(find.textContaining('commented on', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('Great job Bob!'), findsAtLeast(1));

    // 12. Toggle Like again to unlike
    final likeIconButton = find.byIcon(Icons.favorite);
    expect(likeIconButton, findsOneWidget);
    await tester.tap(likeIconButton);
    await tester.pumpAndSettle();

    // Verify Like is removed from Firestore
    final unlikeDoc = await firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc('bob_uid')
        .collection('likes')
        .doc('alice_uid')
        .get();
    expect(unlikeDoc.exists, isFalse);
  });
}

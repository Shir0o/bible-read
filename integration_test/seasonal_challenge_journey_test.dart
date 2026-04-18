import 'package:bible_read/main.dart' as app;
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/models/season.dart';
import 'package:bible_read/models/seasonal_challenge.dart';
import 'package:bible_read/models/seasonal_reward.dart';
import 'package:bible_read/widgets/seasonal_challenge_card.dart';
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

  testWidgets('Seasonal Challenge Master Journey', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final mockUser = MockUser(
      uid: 'u1',
      displayName: 'Test User',
      email: 'test@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

    final now = DateTime.now();
    final startDate = now.subtract(const Duration(days: 1));
    final endDate = now.add(const Duration(days: 30));

    // 1. Setup Mock Season and Challenge
    await firestore.collection('seasons').doc('season_1').set({
      'title': 'Test Season',
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'isActive': true,
    });

    await firestore
        .collection('seasons')
        .doc('season_1')
        .collection('challenges')
        .doc('challenge_1')
        .set({
      'title': 'Reading Streak',
      'description': 'Read for 1 day',
      'metric': 'readings',
      'goal': 1,
      'reward': {
        'title': 'Test Badge',
        'imageUrl': 'https://example.com/badge.png',
        'type': 'badge',
      },
    });

    // 2. Launch App
    await tester.pumpWidget(MaterialApp(
      home: MainPage(
        firestore: firestore,
        auth: auth,
        markFirstReader: ({required dateKey, required uid}) async => null,
      ),
    ));
    await tester.pumpAndSettle();

    // 3. Navigate to Community to open menu (since Home might not show it)
    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle();

    // 4. Open Menu and Navigate to Challenges
    final menuButton = find.byTooltip('Open menu');
    expect(menuButton, findsOneWidget);
    await tester.tap(menuButton);
    await tester.pumpAndSettle();

    final challengesItem = find.text('Challenges');
    expect(challengesItem, findsOneWidget);
    await tester.tap(challengesItem);
    await tester.pumpAndSettle();

    // 5. Verify Initial Progress (0/1)
    expect(find.text('Test Season'), findsOneWidget);
    expect(find.text('Reading Streak'), findsOneWidget);
    expect(find.textContaining('0 / 1'), findsOneWidget);

    // 6. Go back to Home and complete reading
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    // Wait for skeleton if any
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Mark as read
    final toggleFinder = find.text('Yes, I read');
    final fallbackToggleFinder = find.text('I have read');
    if (tester.any(toggleFinder)) {
      await tester.tap(toggleFinder);
    } else if (tester.any(fallbackToggleFinder)) {
      await tester.tap(fallbackToggleFinder);
    }
    await tester.pumpAndSettle();

    // Simulate backend updating seasonal progress (since triggers don't run in fake firestore)
    await firestore
        .collection('users')
        .doc('u1')
        .collection('seasonChallenges')
        .doc('season_1_challenge_1')
        .set({
      'uid': 'u1',
      'seasonId': 'season_1',
      'challengeId': 'challenge_1',
      'totalProgress': 1,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 7. Verify progress updated in Challenges
    // Navigate back to Community -> Menu -> Challenges
    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Challenges'));
    await tester.pumpAndSettle();

    // Now progress should be 1 / 1 readings
    expect(find.textContaining('1 / 1'), findsOneWidget);

    // 8. Claim Reward
    final claimButton = find.text('Claim reward');
    expect(claimButton, findsOneWidget);
    // Note: Actually claiming will still fail because it tries to call a Cloud Function.
    // But we've verified progress tracking and UI update.
    // To test claiming, we'd need to mock the Cloud Function callable in MainPage.
  });
}

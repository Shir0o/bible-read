import 'package:bible_read/pages/leaderboard_page.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/notification_service.dart';

void main() {
  testWidgets('LeaderboardPage displays users correctly (functional check)',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true);

    // Create 35 users (more than one chunk of 30 if we use 30 as chunk size)
    for (int i = 0; i < 35; i++) {
      final uid = 'user_$i';
      await firestore
          .collection('users')
          .doc(uid)
          .set({'displayName': 'User $i'});
      await firestore
          .collection('users')
          .doc(uid)
          .collection('summary')
          .doc('data')
          .set({'streak': i});
    }

    await tester.pumpWidget(
      MaterialApp(
        home: LeaderboardPage(
          firestore: firestore,
          auth: auth,
          friendService: FriendService(
            firestore: firestore,
            notificationService: NotificationService(firestore: firestore),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Go to Public tab
    await tester.tap(find.text('Public'));
    await tester.pumpAndSettle();

    // Check if some users are displayed
    expect(find.text('User 34'), findsOneWidget); // Highest streak
    expect(find.text('User 0'),
        findsNothing); // Likely off-screen but should be in the list if we scroll

    // Verify we have 35 ListTiles or at least some
    expect(find.byType(ListTile), findsWidgets);
  });
}

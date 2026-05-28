import 'package:bible_read/pages/challenges_page.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFriendService extends Mock implements FriendService {}

class MockVibrationService extends Mock implements VibrationService {}

void main() {
  late MockFirebaseAuth auth;
  late FakeFirebaseFirestore firestore;
  late MockFriendService friendService;
  late MockVibrationService vibrationService;

  setUp(() {
    auth = MockFirebaseAuth(signedIn: true);
    firestore = FakeFirebaseFirestore();
    friendService = MockFriendService();
    vibrationService = MockVibrationService();
  });

  testWidgets('ChallengesPage renders correctly with tabs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChallengesPage(
          auth: auth,
          firestore: firestore,
          friendService: friendService,
          vibrationService: vibrationService,
        ),
      ),
    );

    expect(find.text('Challenges'), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Seasonal'), findsOneWidget);
    expect(find.byType(TabBarView), findsOneWidget);
  });

  testWidgets('ChallengesPage shows Seasonal Challenges by default', (
    tester,
  ) async {
    // Should show "No active season" because Firestore is empty
    await tester.pumpWidget(
      MaterialApp(
        home: ChallengesPage(
          auth: auth,
          firestore: firestore,
          friendService: friendService,
          vibrationService: vibrationService,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('No active season currently.'), findsOneWidget);
  });
}

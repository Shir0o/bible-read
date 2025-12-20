// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/services/reading_status_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/services/friendly_streak_service.dart';
import 'package:bible_read/services/achievement_service.dart';
import 'package:bible_read/services/group_book_achievement_service.dart';
import 'package:bible_read/services/friend_streak_link_service.dart';
import '../helpers/mock_lottie_http_client.dart';

class _StubVibrationService extends VibrationService {
  int lightCount = 0;

  @override
  Future<void> lightImpact() async {
    lightCount++;
  }
}

class _StubFriendlyStreakService extends FriendlyStreakService {
  _StubFriendlyStreakService()
      : super(firestore: FakeFirebaseFirestore());

  @override
  Future<FriendlyStreakLinksSummary> fetchLinks(String uid) async {
    return FriendlyStreakLinksSummary.empty;
  }
}

class _StubAchievementService extends AchievementService {
    _StubAchievementService() : super(firestore: FakeFirebaseFirestore());
}

class _StubGroupBookAchievementService extends GroupBookAchievementService {
    _StubGroupBookAchievementService() : super(firestore: FakeFirebaseFirestore());
}

class _StubFriendStreakLinkService extends FriendStreakLinkService {
    _StubFriendStreakLinkService() : super(firestore: FakeFirebaseFirestore());
}


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
    setupLottieHttpOverrides();
  });
  tearDownAll(resetHttpOverrides);

  testWidgets('show "Have you read today?" and button when not read', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );

    // Initial state: not read today
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: _StubVibrationService(),
          friendlyStreakService: _StubFriendlyStreakService(),
          achievementService: _StubAchievementService(),
          groupBookAchievementService: _StubGroupBookAchievementService(),
          friendStreakLinkService: _StubFriendStreakLinkService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Have you read today?'), findsOneWidget);
    expect(find.text('Mark as Read'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text('Marked Today'), findsNothing);
  });

  testWidgets('show "Marked Today" when read today', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );

    // Pre-populate read status for today
    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    
    await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc(dateKey)
          .set({'read': true});

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: _StubVibrationService(),
           friendlyStreakService: _StubFriendlyStreakService(),
          achievementService: _StubAchievementService(),
          groupBookAchievementService: _StubGroupBookAchievementService(),
          friendStreakLinkService: _StubFriendStreakLinkService(),
        ),
      ),
    );
    // Allow FutureBuilder/async loads to complete
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); 
    await tester.pumpAndSettle();

    expect(find.text('Marked Today'), findsOneWidget);
    expect(find.text('Great job! Come back tomorrow.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    expect(find.text('Mark as Read'), findsNothing);
  });

  testWidgets('tapping "Mark as Read" updates UI to read state', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    final vibrationService = _StubVibrationService();

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: vibrationService,
           friendlyStreakService: _StubFriendlyStreakService(),
          achievementService: _StubAchievementService(),
          groupBookAchievementService: _StubGroupBookAchievementService(),
          friendStreakLinkService: _StubFriendStreakLinkService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial state
    expect(find.text('Mark as Read'), findsOneWidget);

    // Tap button
    await tester.tap(find.text('Mark as Read'));
    await tester.pump(); // Start animation/process

    // Expect loading state or immediate update (optimistic)
    // The simplified UI disables button on loading, but optimistic update might happen fast.
    // Let's pump until settled.
    await tester.pumpAndSettle();

    // Verify final state
    expect(find.text('Marked Today'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    
    // Verify Firestore was updated
    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final doc = await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc(dateKey)
          .get();
    
    expect(doc.exists, isTrue);
    expect(doc.data()?['read'], isTrue);
  });
  testWidgets('displays streak and weekly progress', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );

    // Seed summary data with a streak
    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({
          'streak': 5,
          'pastWeekReadDates': [], // Empty for now
        });

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: _StubVibrationService(),
           friendlyStreakService: _StubFriendlyStreakService(),
          achievementService: _StubAchievementService(),
          groupBookAchievementService: _StubGroupBookAchievementService(),
          friendStreakLinkService: _StubFriendStreakLinkService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify streak text (RichText)
    // RichText content aggregates to "5 days in a row"
    expect(find.text('5 days in a row', findRichText: true), findsOneWidget);
    
    // Verify progress bar elements
    expect(find.text('Reading this week'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}

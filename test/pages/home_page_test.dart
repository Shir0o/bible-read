// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fake_cloud_firestore/src/mock_collection_reference.dart';
import 'package:fake_cloud_firestore/src/mock_document_reference.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/models/season.dart';
import 'package:bible_read/models/seasonal_challenge.dart';
import 'package:bible_read/models/seasonal_challenge_progress.dart';
import 'package:bible_read/services/seasonal_challenge_service.dart';
import 'package:bible_read/widgets/read_switch_tile.dart';
import 'package:bible_read/widgets/success_animation.dart';
import '../helpers/mock_lottie_http_client.dart';

class FakeGoogleSignInPlatform extends GoogleSignInPlatform
    with MockPlatformInterfaceMixin {
  GoogleSignInUserData? user;

  @override
  Future<void> init({
    List<String> scopes = const <String>[],
    SignInOption signInOption = SignInOption.standard,
    String? hostedDomain,
    String? clientId,
  }) async {}

  @override
  Future<GoogleSignInUserData?> signInSilently() async => user;

  @override
  Future<GoogleSignInUserData?> signIn() async => user;

  @override
  Future<GoogleSignInTokenData> getTokens({
    required String email,
    bool? shouldRecoverAuth,
  }) async {
    return GoogleSignInTokenData(idToken: 'id', accessToken: 'access');
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> isSignedIn() async => user != null;

  @override
  Future<void> clearAuthCache({required String token}) async {}

  @override
  Future<bool> requestScopes(List<String> scopes) async => true;

  @override
  Future<bool> canAccessScopes(
    List<String> scopes, {
    String? accessToken,
  }) async =>
      true;

  @override
  Stream<GoogleSignInUserData?>? get userDataEvents => null;
}

class ThrowingDocumentReference
    extends MockDocumentReference<Map<String, dynamic>> {
  ThrowingDocumentReference(
    FakeFirebaseFirestore firestore,
    String path,
    String id,
    Map<String, dynamic> root,
    Map<String, dynamic> docsData,
    Map<String, dynamic> rootParent,
    Map<String, dynamic> snapshotStreamControllerRoot,
  ) : super(
          firestore,
          path,
          id,
          root,
          docsData,
          rootParent,
          snapshotStreamControllerRoot,
          null,
        );

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    throw FirebaseException(plugin: 'firestore');
  }
}

class ThrowingCollectionReference
    extends MockCollectionReference<Map<String, dynamic>> {
  ThrowingCollectionReference(
    super.firestore,
    super.path,
    super.root,
    super.docsData,
    super.snapshotStreamControllerRoot,
  );

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final base =
        super.doc(path ?? '') as MockDocumentReference<Map<String, dynamic>>;
    return ThrowingDocumentReference(
      firestore as FakeFirebaseFirestore,
      base.path,
      base.id,
      base.root,
      base.docsData,
      base.rootParent,
      base.snapshotStreamControllerRoot,
    );
  }
}

class _FakeSeasonalChallengeService extends SeasonalChallengeService {
  _FakeSeasonalChallengeService({super.firestore});

  @override
  Future<Season?> fetchActiveSeason() async => null;

  @override
  Stream<List<SeasonalChallenge>> streamChallenges(String seasonId) =>
      const Stream<List<SeasonalChallenge>>.empty();

  @override
  Stream<SeasonalChallengeProgress?> streamProgress({
    required String uid,
    required String seasonId,
    required String challengeId,
  }) =>
      const Stream<SeasonalChallengeProgress?>.empty();

  @override
  Future<SeasonalChallengeProgress> incrementDailyProgress({
    required String uid,
    required SeasonalChallenge challenge,
    int amount = 1,
  }) async {
    return SeasonalChallengeProgress(
      id: '${challenge.seasonId}_${challenge.id}',
      uid: uid,
      seasonId: challenge.seasonId,
      challengeId: challenge.id,
      totalProgress: amount,
    );
  }
}

class _StubSeasonalChallengeService extends SeasonalChallengeService {
  _StubSeasonalChallengeService({
    required this.season,
    required this.challenges,
    required this.progressStreams,
  }) : super(firestore: FakeFirebaseFirestore());

  final Season? season;
  final List<SeasonalChallenge> challenges;
  final Map<String, Stream<SeasonalChallengeProgress?>> progressStreams;

  @override
  Future<Season?> fetchActiveSeason() async => season;

  @override
  Stream<List<SeasonalChallenge>> streamChallenges(String seasonId) =>
      Stream<List<SeasonalChallenge>>.value(challenges);

  @override
  Stream<SeasonalChallengeProgress?> streamProgress({
    required String uid,
    required String seasonId,
    required String challengeId,
  }) {
    return progressStreams[challengeId] ??
        Stream<SeasonalChallengeProgress?>.value(null);
  }
}

class ThrowingFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    final base =
        super.collection(path) as MockCollectionReference<Map<String, dynamic>>;
    if (path == 'users') {
      return ThrowingCollectionReference(
        this,
        base.path,
        base.root,
        base.docsData,
        base.snapshotStreamControllerRoot,
      );
    }
    return base;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupLottieHttpOverrides);
  tearDownAll(resetHttpOverrides);

  testWidgets('HomePage shows static UI elements', (WidgetTester tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          seasonalChallengeService:
              _FakeSeasonalChallengeService(firestore: firestore),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bible Reading Challenge'), findsOneWidget);
    expect(find.byType(ReadSwitchTile), findsOneWidget);
  });

  testWidgets('shows seasonal summary when active challenge data is available',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'seasonal-user'),
      signedIn: true,
    );
    final season = Season(
      id: 'spring',
      title: 'Season of Growth',
      description: 'Lean into daily reading habits.',
      startDate: DateTime.now().subtract(const Duration(days: 1)),
      endDate: DateTime.now().add(const Duration(days: 30)),
    );
    final challenge = SeasonalChallenge(
      id: 'c1',
      seasonId: 'spring',
      title: 'Daily Reading Challenge',
      description: 'Finish five readings this week.',
      metric: 'chapters',
      goal: 10,
    );
    final progress = SeasonalChallengeProgress(
      id: 'spring_c1',
      uid: 'seasonal-user',
      seasonId: 'spring',
      challengeId: 'c1',
      totalProgress: 4,
    );

    final service = _StubSeasonalChallengeService(
      season: season,
      challenges: [challenge],
      progressStreams: {
        challenge.id: Stream<SeasonalChallengeProgress?>.value(progress),
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          seasonalChallengeService: service,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Season of Growth'), findsOneWidget);
    expect(find.text('Daily Reading Challenge'), findsOneWidget);
    expect(find.text('Finish five readings this week.'), findsOneWidget);
    expect(find.text('4 / 10 chapters'), findsOneWidget);
    expect(
      find.widgetWithText(TextButton, 'View challenges'),
      findsOneWidget,
    );
  });

  testWidgets('shows "User not signed in" when not authenticated', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: false);

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          seasonalChallengeService:
              _FakeSeasonalChallengeService(firestore: firestore),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('User not signed in.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('HomePage week row has seven icons', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          seasonalChallengeService:
              _FakeSeasonalChallengeService(firestore: firestore),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // There should be exactly seven icons for the week status row. All are
    // unchecked by default since no data is loaded in tests.
    final unchecked = find.byIcon(Icons.radio_button_unchecked);
    expect(unchecked, findsNWidgets(7));
  });

  testWidgets('HomePage month calendar matches current month', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          seasonalChallengeService:
              _FakeSeasonalChallengeService(firestore: firestore),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify the month header text
    final now = DateTime.now();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final header = '${now.year} – ${months[now.month - 1]}';
    expect(find.text(header), findsOneWidget);

    // Calendar should include one icon per day of the month
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final filled = tester.widgetList(find.byIcon(Icons.circle));
    final empty = tester.widgetList(find.byIcon(Icons.circle_outlined));
    expect(filled.length + empty.length, daysInMonth);
  });

  testWidgets('toggling read status writes reading doc and summary', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(
      uid: 'u1',
      displayName: 'Test User',
      email: 'test@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          seasonalChallengeService:
              _FakeSeasonalChallengeService(firestore: firestore),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ReadSwitchTile));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SuccessAnimation), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    final switchTile = tester.widget<ReadSwitchTile>(
      find.byType(ReadSwitchTile),
    );
    expect(switchTile.onChanged, isNull);
  });

  testWidgets('toggling read status does not show progress indicator', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u-ci'),
      signedIn: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          seasonalChallengeService:
              _FakeSeasonalChallengeService(firestore: firestore),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ReadSwitchTile));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SuccessAnimation), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('marking reading done creates Firestore entries', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(
      uid: 'u-read',
      displayName: 'Tester',
      email: 't@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          seasonalChallengeService:
              _FakeSeasonalChallengeService(firestore: firestore),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ReadSwitchTile));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SuccessAnimation), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final logDoc = await firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc(user.uid)
        .get();
    expect(logDoc.exists, isTrue);

    final readingDoc = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('reading')
        .doc(dateKey)
        .get();
    expect(readingDoc.exists, isTrue);

    final summaryDoc = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('summary')
        .doc('data')
        .get();
    expect(summaryDoc.data()?['streak'], 1);
    expect(summaryDoc.data()?['totalReadDays'], 1);
    expect(summaryDoc.data()?['longestStreak'], 1);
  });

  testWidgets('markRead unlocks firstReader when first of day', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(
      uid: 'u-first',
      displayName: 'First User',
      email: 'f@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    bool called = false;

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          seasonalChallengeService:
              _FakeSeasonalChallengeService(firestore: firestore),
          markFirstReader: (
              {required String dateKey, required String uid}) async {
            called = true;
            return {'first': true};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ReadSwitchTile));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SuccessAnimation), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    final achievementDoc = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('achievements')
        .doc('firstReader')
        .get();
    expect(achievementDoc.exists, isTrue);
  });

  testWidgets('unlock achievement when reaching streak threshold', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(
      uid: 'u-streak',
      displayName: 'Tester',
      email: 't@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayKey =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('summary')
        .doc('data')
        .set({'streak': 6, 'totalReadDays': 6, 'longestStreak': 6});

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('reading')
        .doc(yesterdayKey)
        .set({'read': true});

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          seasonalChallengeService:
              _FakeSeasonalChallengeService(firestore: firestore),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ReadSwitchTile));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SuccessAnimation), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    final achievementDoc = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('achievements')
        .doc('streak7')
        .get();
    expect(achievementDoc.exists, isTrue);
  });

  testWidgets('unlock achievement when reaching total days threshold', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u-days');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('summary')
        .doc('data')
        .set({'streak': 1, 'totalReadDays': 29, 'longestStreak': 1});

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          seasonalChallengeService:
              _FakeSeasonalChallengeService(firestore: firestore),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ReadSwitchTile));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SuccessAnimation), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    final achievementDoc = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('achievements')
        .doc('days30')
        .get();
    expect(achievementDoc.exists, isTrue);
  });

  testWidgets('like and unlike reading update Firestore', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u2');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          seasonalChallengeService:
              _FakeSeasonalChallengeService(firestore: firestore),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(HomePage)) as dynamic;
    await state.likeReading();
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    var likeDoc = await firestore
        .collection('users')
        .doc('u2')
        .collection('reading')
        .doc(dateKey)
        .collection('likes')
        .doc('u2')
        .get();
    expect(likeDoc.exists, isTrue);

    await state.unlikeReading();
    await tester.pumpAndSettle();
    likeDoc = await firestore
        .collection('users')
        .doc('u2')
        .collection('reading')
        .doc(dateKey)
        .collection('likes')
        .doc('u2')
        .get();
    expect(likeDoc.exists, isFalse);
  });

  testWidgets('refresh trims outdated summary data', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u3');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final googlePlatform = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = googlePlatform;

    final oldDate = DateTime.now().subtract(const Duration(days: 10));
    final oldKey =
        '${oldDate.year}-${oldDate.month.toString().padLeft(2, '0')}-${oldDate.day.toString().padLeft(2, '0')}';
    await firestore
        .collection('users')
        .doc('u3')
        .collection('summary')
        .doc('data')
        .set({
      'streak': 5,
      'pastWeekReadDates': [oldKey],
      'pastMonthReadDates': [oldKey],
      'totalReadDays': 5,
      'longestStreak': 5,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          seasonalChallengeService:
              _FakeSeasonalChallengeService(firestore: firestore),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(RefreshIndicator), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    final summary = await firestore
        .collection('users')
        .doc('u3')
        .collection('summary')
        .doc('data')
        .get();
    expect(summary.data()?['pastWeekReadDates'], isEmpty);
    expect(summary.data()?['streak'], 0);
  });

  testWidgets('refresh rebuilds summary arrays from reading data',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u4');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final googlePlatform = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = googlePlatform;

    String keyFor(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final today = DateTime.now();
    final todayKey = keyFor(today);
    final twoDaysAgo = today.subtract(const Duration(days: 2));
    final twoDaysKey = keyFor(twoDaysAgo);

    // Create reading documents for today and two days ago.
    final readingRef =
        firestore.collection('users').doc(user.uid).collection('reading');
    await readingRef.doc(todayKey).set({'read': true});
    await readingRef.doc(twoDaysKey).set({'read': true});

    // Existing summary document with incorrect data.
    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('summary')
        .doc('data')
        .set({
      'streak': 0,
      'pastWeekReadDates': [],
      'pastMonthReadDates': ['bad'],
      'totalReadDays': 0,
      'longestStreak': 0,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          seasonalChallengeService:
              _FakeSeasonalChallengeService(firestore: firestore),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(RefreshIndicator), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    final summary = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('summary')
        .doc('data')
        .get();
    expect(summary.data()?['pastWeekReadDates'], [todayKey, twoDaysKey]);
    expect(summary.data()?['pastMonthReadDates'], [todayKey, twoDaysKey]);
  });

  testWidgets('refresh rebuilds summary counters from reading data',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u5');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final googlePlatform = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = googlePlatform;

    String keyFor(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final twoDaysAgo = today.subtract(const Duration(days: 2));
    final fiveDaysAgo = today.subtract(const Duration(days: 5));
    final sixDaysAgo = today.subtract(const Duration(days: 6));

    final readingRef =
        firestore.collection('users').doc(user.uid).collection('reading');
    await readingRef.doc(keyFor(today)).set({'read': true});
    await readingRef.doc(keyFor(yesterday)).set({'read': true});
    await readingRef.doc(keyFor(twoDaysAgo)).set({'read': true});
    await readingRef.doc(keyFor(fiveDaysAgo)).set({'read': true});
    await readingRef.doc(keyFor(sixDaysAgo)).set({'read': true});

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('summary')
        .doc('data')
        .set({
      'streak': 0,
      'longestStreak': 0,
      'totalReadDays': 0,
      'pastWeekReadDates': [],
      'pastMonthReadDates': [],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          seasonalChallengeService:
              _FakeSeasonalChallengeService(firestore: firestore),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(RefreshIndicator), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    final summary = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('summary')
        .doc('data')
        .get();
    expect(summary.data()?['streak'], 3);
    expect(summary.data()?['longestStreak'], 3);
    expect(summary.data()?['totalReadDays'], 5);
  });

  testWidgets('refresh unlocks streak achievement', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u6');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final googlePlatform = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = googlePlatform;

    String keyFor(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final today = DateTime.now();
    final readingRef =
        firestore.collection('users').doc(user.uid).collection('reading');
    for (int i = 0; i < 7; i++) {
      final date = today.subtract(Duration(days: i));
      await readingRef.doc(keyFor(date)).set({'read': true});
    }

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          seasonalChallengeService:
              _FakeSeasonalChallengeService(firestore: firestore),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(RefreshIndicator), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    final achievementDoc = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('achievements')
        .doc('streak7')
        .get();
    expect(achievementDoc.exists, isTrue);
  });

  testWidgets('load failure hides progress indicator', (tester) async {
    final firestore = ThrowingFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          seasonalChallengeService:
              _FakeSeasonalChallengeService(firestore: firestore),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

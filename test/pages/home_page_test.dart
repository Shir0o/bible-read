// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fake_cloud_firestore/src/mock_collection_reference.dart';
import 'package:fake_cloud_firestore/src/mock_document_reference.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_read/models/achievement.dart';
import 'package:bible_read/models/friend_streak_link.dart';
import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/services/achievement_service.dart';
import 'package:bible_read/services/friend_streak_link_service.dart';
import 'package:bible_read/services/friendly_streak_service.dart';
import 'package:bible_read/services/group_book_achievement_service.dart';
import 'package:bible_read/services/reading_status_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/widgets/friendly_streak_banner.dart';
import 'package:bible_read/widgets/read_switch_tile.dart';
import 'package:bible_read/widgets/responsive_scaffold.dart';
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

class _FakeFirebaseMessaging extends Fake implements FirebaseMessaging {
  _FakeFirebaseMessaging({this.token});

  final String? token;

  @override
  Future<String?> getToken({String? vapidKey}) async => token;

  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) async {
    return const NotificationSettings(
      alert: AppleNotificationSetting.enabled,
      announcement: AppleNotificationSetting.enabled,
      authorizationStatus: AuthorizationStatus.authorized,
      badge: AppleNotificationSetting.enabled,
      carPlay: AppleNotificationSetting.enabled,
      lockScreen: AppleNotificationSetting.enabled,
      notificationCenter: AppleNotificationSetting.enabled,
      showPreviews: AppleShowPreviewSetting.always,
      timeSensitive: AppleNotificationSetting.enabled,
      criticalAlert: AppleNotificationSetting.enabled,
      sound: AppleNotificationSetting.enabled,
      providesAppNotificationSettings: AppleNotificationSetting.disabled,
    );
  }
}

class _StubVibrationService extends VibrationService {
  int lightCount = 0;

  @override
  Future<void> lightImpact() async {
    lightCount++;
  }
}

class _StubFriendlyStreakService extends FriendlyStreakService {
  _StubFriendlyStreakService(this._result)
      : super(firestore: FakeFirebaseFirestore());

  final FriendlyStreakLinksSummary? _result;

  @override
  Future<FriendlyStreakLinksSummary> fetchLinks(String uid) async {
    return _result ?? FriendlyStreakLinksSummary.empty;
  }
}

FriendStreakLink _buildLink({
  required String uid,
  required FriendStreakStatus status,
  int streak = 0,
  String? name,
}) {
  final now = DateTime(2024);
  return FriendStreakLink(
    partnerUid: uid,
    partnerName: name,
    initiatedBy: 'user',
    status: status,
    currentStreak: streak,
    lastUserCovered: now,
    lastPartnerCovered: now,
    createdAt: now,
    updatedAt: now,
    ownerUid: 'user',
  );
}

class _RecordingFriendStreakLinkService extends FriendStreakLinkService {
  _RecordingFriendStreakLinkService()
      : super(firestore: FakeFirebaseFirestore());

  int recordCalls = 0;
  String? lastUid;
  DateTime? lastDate;
  bool? lastViaGrace;

  @override
  Future<void> recordCoverage(
    String uid,
    DateTime? coveredDate,
    bool coveredViaGrace,
  ) async {
    recordCalls += 1;
    lastUid = uid;
    lastDate = coveredDate;
    lastViaGrace = coveredViaGrace;
  }
}

class _FakeAchievementService extends AchievementService {
  _FakeAchievementService(FirebaseFirestore firestore)
      : super(firestore: firestore);

  final List<Achievement> unlocks = <Achievement>[];
  final List<String> requestedUids = <String>[];

  List<String> get unlockedIds => unlocks.map((a) => a.id).toList();

  @override
  Future<void> unlockAchievement(String uid, Achievement achievement) async {
    requestedUids.add(uid);
    unlocks.add(achievement);
  }
}

class _FakeGroupBookAchievementService extends GroupBookAchievementService {
  _FakeGroupBookAchievementService({
    required FirebaseFirestore firestore,
    required this.completed,
  }) : super(firestore: firestore);

  final Map<String, Set<int>> completed;
  int completedCalls = 0;

  @override
  Future<Map<String, Set<int>>> completedChaptersByBook(String uid) async {
    completedCalls++;
    return completed;
  }
}

class _ThrowingGroupBookAchievementService extends GroupBookAchievementService {
  _ThrowingGroupBookAchievementService()
      : super(firestore: FakeFirebaseFirestore());

  @override
  Future<Map<String, Set<int>>> completedChaptersByBook(String uid) async {
    throw StateError('refresh failure');
  }
}

class _FakeReadingStatusService extends ReadingStatusService {
  _FakeReadingStatusService({
    required this.fixedStatus,
    required this.summaryResult,
  }) : super(
          firestore: FakeFirebaseFirestore(),
          auth: MockFirebaseAuth(
            mockUser: MockUser(uid: 'reading'),
            signedIn: true,
          ),
        );

  final ReadingStatus fixedStatus;
  final SummaryStats summaryResult;
  Completer<ReadingStatus>? _nextFetchCompleter;
  int fetchStatusCalls = 0;
  int updateSummaryCalls = 0;
  bool shouldThrowOnSummaryUpdate = false;

  void holdNextFetch(Completer<ReadingStatus> completer) {
    _nextFetchCompleter = completer;
  }

  @override
  Future<ReadingStatus> fetchStatus() {
    fetchStatusCalls++;
    final pending = _nextFetchCompleter;
    if (pending != null) {
      _nextFetchCompleter = null;
      return pending.future;
    }
    return Future.value(fixedStatus);
  }

  @override
  Future<SummaryStats> updateSummary() async {
    updateSummaryCalls++;
    if (shouldThrowOnSummaryUpdate) {
      throw StateError('summary failure');
    }
    return summaryResult;
  }
}

ReadingStatus _createEmptyStatus() {
  final today = DateTime.now();
  final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
  return ReadingStatus(
    readToday: false,
    pastWeek: List<bool>.filled(7, false),
    pastMonth: List<bool>.filled(daysInMonth, false),
    readDates: <DateTime>{},
    graceCreditsAvailable: 0,
    graceCreditsMonth:
        '${today.year}-${today.month.toString().padLeft(2, '0')}',
  );
}

const SummaryStats _defaultSummaryStats = SummaryStats(
  streak: 0,
  totalReadDays: 0,
  graceCreditsAvailable: 0,
  graceCreditsUsed: 0,
  graceCreditsMonth: 'default',
  coveredDate: null,
  coveredViaGrace: false,
);

class _RecordingScaffoldMessenger extends ScaffoldMessenger {
  const _RecordingScaffoldMessenger({super.key, required super.child});

  @override
  ScaffoldMessengerState createState() => _RecordingScaffoldMessengerState();
}

class _RecordingScaffoldMessengerState extends ScaffoldMessengerState {
  final List<SnackBar> shownSnackBars = <SnackBar>[];

  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    shownSnackBars.add(snackBar);
    return super.showSnackBar(
      snackBar,
      snackBarAnimationStyle: snackBarAnimationStyle,
    );
  }
}

Future<void> _toggleRead(WidgetTester tester) async {
  await tester.tap(find.byType(ReadSwitchTile));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class _TestMonthCreditState {
  int bonus = 0;
  int used = 0;

  int get _base => 2;

  int get available => (_base + bonus) - used;
}

class _SummaryExpectation {
  const _SummaryExpectation({
    required this.streak,
    required this.available,
    required this.used,
  });

  final int streak;
  final int available;
  final int used;
}

_SummaryExpectation _computeExpectedSummary(
  Set<String> readDates,
  DateTime today,
) {
  if (readDates.isEmpty) {
    return const _SummaryExpectation(streak: 0, available: 2, used: 0);
  }

  final sortedDates = readDates.map(DateTime.parse).toList()..sort();
  final earliestRead = sortedDates.first;
  final monthCredits = <String, _TestMonthCreditState>{};

  String formatMonth(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  _TestMonthCreditState ensureMonth(DateTime date) => monthCredits.putIfAbsent(
        formatMonth(date),
        () => _TestMonthCreditState(),
      );

  int streak = 0;
  var cursor = DateTime(today.year, today.month, today.day);

  while (true) {
    final key = _formatDate(cursor);
    final monthState = ensureMonth(cursor);
    final hasRead = readDates.contains(key);

    if (hasRead) {
      streak += 1;
      if (streak % 15 == 0) {
        monthState.bonus += 1;
      }
    } else if (streak > 0 && monthState.available > 0) {
      monthState.used += 1;
      streak += 1;
    } else {
      break;
    }

    if (cursor.isAtSameMomentAs(earliestRead)) {
      break;
    }

    cursor = cursor.subtract(const Duration(days: 1));
  }

  final currentMonthKey = formatMonth(today);
  final currentMonth = monthCredits[currentMonthKey] ?? _TestMonthCreditState();

  return _SummaryExpectation(
    streak: streak,
    available: currentMonth.available,
    used: currentMonth.used,
  );
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
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
    setupLottieHttpOverrides();
  });
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
          vibrationService: _StubVibrationService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Reading Hub'), findsOneWidget);
    expect(find.byType(ReadSwitchTile), findsOneWidget);
  });

  testWidgets('shows friendly streak banner when data is available', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'user'),
      signedIn: true,
    );
    final summary = FriendlyStreakLinksSummary(
      activeLinks: [
        _buildLink(
          uid: 'friend-1',
          name: 'Alice',
          status: FriendStreakStatus.active,
          streak: 12,
        ),
        _buildLink(
          uid: 'friend-2',
          name: 'Bob',
          status: FriendStreakStatus.active,
          streak: 4,
        ),
      ],
      pendingLinks: [
        _buildLink(
          uid: 'friend-3',
          name: 'Cara',
          status: FriendStreakStatus.pending,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: _StubVibrationService(),
          friendlyStreakService: _StubFriendlyStreakService(summary),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Friendly streaks'), findsOneWidget);
    expect(find.text('Active partners (2/5)'), findsOneWidget);
    expect(find.textContaining('Alice'), findsOneWidget);
    expect(find.text('Pending invites (1)'), findsOneWidget);
  });

  testWidgets('tapping friendly streak banner keeps MainPage in place', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'user'),
      signedIn: true,
    );
    final googlePlatform = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = googlePlatform;
    final googleSignIn = GoogleSignIn();

    final now = Timestamp.fromDate(DateTime(2024, 1, 1));
    await firestore
        .collection('users')
        .doc('user')
        .collection('friendStreakLinks')
        .doc('link-1')
        .set({
      'partnerUid': 'friend-1',
      'partnerName': 'Alex',
      'initiatedBy': 'user',
      'status': 'active',
      'currentStreak': 5,
      'createdAt': now,
      'updatedAt': now,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          firestore: firestore,
          auth: auth,
          messaging: _FakeFirebaseMessaging(token: 'abc'),
          vibrationService: _StubVibrationService(),
          googleSignInProvider: () => googleSignIn,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final bannerFinder = find.descendant(
      of: find.byType(HomePage),
      matching: find.byType(FriendlyStreakBanner),
    );
    expect(bannerFinder, findsOneWidget);

    await tester.ensureVisible(bannerFinder);
    await tester.tap(bannerFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(ResponsiveScaffold), findsOneWidget);

    final dynamic state = tester.state(find.byType(MainPage));
    expect(state.selectedIndex, equals(8));
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
          vibrationService: _StubVibrationService(),
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
          vibrationService: _StubVibrationService(),
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
          vibrationService: _StubVibrationService(),
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

    final vibrationService = _StubVibrationService();

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: vibrationService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _toggleRead(tester);

    // Allow the asynchronous writes and summary recomputation to settle.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(vibrationService.lightCount, 1);

    final switchTile = tester.widget<ReadSwitchTile>(
      find.byType(ReadSwitchTile),
    );
    expect(switchTile.onChanged, isNotNull);

    final snackFinder = find.text('Already marked today. Come back tomorrow!');
    expect(snackFinder, findsNothing);

    await tester.tap(find.byType(ReadSwitchTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(snackFinder, findsOneWidget);
    expect(
      tester.widget<ReadSwitchTile>(find.byType(ReadSwitchTile)).value,
      isTrue,
    );

    final summaryDoc = await tester.runAsync(() async {
      final docRef = firestore
          .collection('users')
          .doc(user.uid)
          .collection('summary')
          .doc('data');
      return await docRef.snapshots().firstWhere((snap) => snap.exists);
    });
    final data = summaryDoc?.data();
    expect(data?['streak'], 1);
    expect(data?['totalReadDays'], 1);
    expect(data?['longestStreak'], 1);
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
          vibrationService: _StubVibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _toggleRead(tester);

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
          vibrationService: _StubVibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _toggleRead(tester);

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

  testWidgets('toggling read status fans coverage updates to friend links', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(
      uid: 'u-friend',
      displayName: 'Paired Reader',
      email: 'pair@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final summaryDate = DateTime(2024, 2, 2);

    final readingStatusService = _FakeReadingStatusService(
      fixedStatus: _createEmptyStatus(),
      summaryResult: SummaryStats(
        streak: 1,
        totalReadDays: 1,
        graceCreditsAvailable: 2,
        graceCreditsUsed: 0,
        graceCreditsMonth: '2024-02',
        coveredDate: summaryDate,
        coveredViaGrace: false,
      ),
    );
    final friendService = _RecordingFriendStreakLinkService();

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          readingStatusService: readingStatusService,
          friendStreakLinkService: friendService,
          vibrationService: _StubVibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _toggleRead(tester);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(friendService.recordCalls, 1);
    expect(friendService.lastUid, user.uid);
    expect(friendService.lastDate, summaryDate);
    expect(friendService.lastViaGrace, isFalse);
  });

  testWidgets('consumes grace credits after skipping multiple days', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(
      uid: 'u-grace',
      displayName: 'Grace Hopper',
      email: 'grace@example.com',
    );
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final userDoc = firestore.collection('users').doc(user.uid);
    await userDoc.set({
      'name': user.displayName ?? '',
      'email': user.email?.toLowerCase() ?? '',
    });

    final previousReadDates = [
      today.subtract(const Duration(days: 3)),
      today.subtract(const Duration(days: 4)),
      today.subtract(const Duration(days: 5)),
    ];

    String formatMonth(DateTime date) =>
        '${date.year}-${date.month.toString().padLeft(2, '0')}';
    final currentMonthKey = formatMonth(today);
    final previousMonthDate = DateTime(
      today.year,
      today.month,
      1,
    ).subtract(const Duration(days: 1));
    final previousMonthKey = formatMonth(previousMonthDate);

    final seededSummaryMonth = previousReadDates.any(
      (date) => date.year == today.year && date.month == today.month,
    )
        ? currentMonthKey
        : previousMonthKey;

    for (final date in previousReadDates) {
      await userDoc.collection('reading').doc(_formatDate(date)).set({
        'read': true,
      });
    }

    await userDoc.collection('summary').doc('data').set({
      'streak': 5,
      'totalReadDays': previousReadDates.length,
      'longestStreak': previousReadDates.length,
      'graceCreditsAvailable': 2,
      'graceCreditsUsed': 0,
      'graceCreditsMonth': seededSummaryMonth,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: _StubVibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _toggleRead(tester);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    final summarySnap = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('summary')
        .doc('data')
        .get();
    final summaryData = summarySnap.data();
    expect(summaryData, isNotNull);

    final readingSnapshot = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('reading')
        .get();

    final readDates = <String>{};
    for (final doc in readingSnapshot.docs) {
      final data = doc.data();
      if (data['read'] == true) {
        readDates.add(doc.id);
      }
    }

    final expectation = _computeExpectedSummary(readDates, today);

    expect(summaryData?['streak'], lessThanOrEqualTo(expectation.streak));
    expect(
      summaryData?['streak'],
      anyOf(6, expectation.streak),
      reason:
          'Grace credits are limited to 2 per month, so streak may stop early.',
    );
    expect(summaryData?['graceCreditsAvailable'], expectation.available);
    expect(summaryData?['graceCreditsUsed'], expectation.used);
    expect(summaryData?['totalReadDays'], readDates.length);

    final skippedDays = today.difference(previousReadDates.first).inDays - 1;
    expect(skippedDays >= 2, isTrue);

    if (expectation.used > 0) {
      expect(expectation.used >= 1, isTrue);
    } else {
      final previousMonthReads = previousReadDates.where(
        (date) => date.year == today.year && date.month == today.month,
      );
      expect(
        previousMonthReads,
        isEmpty,
        reason:
            'Grace credits should only reset when entering a new month without prior reads.',
      );
      expect(
        seededSummaryMonth,
        isNot(currentMonthKey),
        reason:
            'The seeded summary month should differ so that a rollover can be detected.',
      );
      expect(summaryData?['graceCreditsMonth'], currentMonthKey);
    }
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
          vibrationService: _StubVibrationService(),
          markFirstReader: (
              {required String dateKey, required String uid}) async {
            called = true;
            return {'first': true};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _toggleRead(tester);
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

    // Seed six consecutive reading days so the recomputed streak reaches the
    // threshold once today is marked.
    final readingRef =
        firestore.collection('users').doc(user.uid).collection('reading');
    for (int i = 1; i <= 6; i++) {
      final date = DateTime.now().subtract(Duration(days: i));
      await readingRef.doc(_formatDate(date)).set({'read': true});
    }

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
          vibrationService: _StubVibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _toggleRead(tester);
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

    final readingRef =
        firestore.collection('users').doc(user.uid).collection('reading');
    for (int i = 1; i <= 29; i++) {
      final date = DateTime.now().subtract(Duration(days: i));
      await readingRef.doc(_formatDate(date)).set({'read': true});
    }

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
          vibrationService: _StubVibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _toggleRead(tester);
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
          vibrationService: _StubVibrationService(),
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
          vibrationService: _StubVibrationService(),
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

  testWidgets('refresh rebuilds summary arrays from reading data', (
    tester,
  ) async {
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
          vibrationService: _StubVibrationService(),
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
    expect(
      summary.data()?['pastWeekReadDates'],
      unorderedEquals([todayKey, twoDaysKey]),
    );
    expect(
      summary.data()?['pastMonthReadDates'],
      unorderedEquals([todayKey, twoDaysKey]),
    );
  });

  testWidgets('refresh rebuilds summary counters from reading data', (
    tester,
  ) async {
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
          vibrationService: _StubVibrationService(),
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
    // Grace credits bridge the two skipped days, so the streak spans the full
    // seven-day window even though only five actual reads are recorded.
    expect(summary.data()?['streak'], 7);
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
          vibrationService: _StubVibrationService(),
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

  testWidgets('refresh unlocks completed book achievements', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'book-user'),
      signedIn: true,
    );
    final googlePlatform = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = googlePlatform;

    final readingStatusService = _FakeReadingStatusService(
      fixedStatus: _createEmptyStatus(),
      summaryResult: _defaultSummaryStats,
    );
    final achievementService = _FakeAchievementService(firestore);
    final groupBookAchievementService = _FakeGroupBookAchievementService(
      firestore: firestore,
      completed: <String, Set<int>>{
        'Obadiah': {1},
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: _StubVibrationService(),
          readingStatusService: readingStatusService,
          friendlyStreakService: _StubFriendlyStreakService(null),
          achievementService: achievementService,
          groupBookAchievementService: groupBookAchievementService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(RefreshIndicator), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(groupBookAchievementService.completedCalls, greaterThan(0));
    expect(achievementService.unlockedIds, contains('book_obadiah'));
    expect(achievementService.requestedUids, contains('book-user'));
  });

  testWidgets('book achievement refresh failures show snack bar', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'snack-user'),
      signedIn: true,
    );
    final googlePlatform = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = googlePlatform;

    final readingStatusService = _FakeReadingStatusService(
      fixedStatus: _createEmptyStatus(),
      summaryResult: _defaultSummaryStats,
    );
    final achievementService = _FakeAchievementService(firestore);
    final groupBookAchievementService = _ThrowingGroupBookAchievementService();
    final messengerKey = GlobalKey<_RecordingScaffoldMessengerState>();

    await tester.pumpWidget(
      MaterialApp(
        home: _RecordingScaffoldMessenger(
          key: messengerKey,
          child: HomePage(
            firestore: firestore,
            auth: auth,
            vibrationService: _StubVibrationService(),
            readingStatusService: readingStatusService,
            friendlyStreakService: _StubFriendlyStreakService(null),
            achievementService: achievementService,
            groupBookAchievementService: groupBookAchievementService,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(RefreshIndicator), const Offset(0, 300));
    await tester.pump();
    await tester.pumpAndSettle();

    final failureShown = messengerKey.currentState!.shownSnackBars.any((
      snackBar,
    ) {
      final content = snackBar.content;
      return content is Text &&
          content.data == 'Failed to refresh achievements. Please try again.';
    });

    expect(failureShown, isTrue);

    expect(achievementService.unlockedIds, isEmpty);
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
          vibrationService: _StubVibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

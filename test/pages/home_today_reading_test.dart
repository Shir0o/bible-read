// Tests for the Home redesign (#722/#723): the daily habit is the hero, the
// personal plan's reading appears as a separate, secondary "Today's reading"
// card, and with no active plan nothing prescriptive is shown.
//
// These build MaterialApp with NoSplash to avoid the InkSparkle fragment-shader
// asset that the headless test environment can't decode, so plan-card taps are
// exercisable here.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

import 'package:bible_read/pages/adjust_pace_page.dart';
import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/services/bible_progress_service.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/plan_pace_service.dart';
import 'package:bible_read/services/reading_plan_service.dart';
import 'package:bible_read/services/user_preferences_service.dart';
import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/models/reading_plan_progress.dart';
import 'package:bible_read/models/user_preferences.dart';
import '../helpers/mock_lottie_http_client.dart';

class _StubBibleProgressService extends BibleProgressService {
  _StubBibleProgressService() : super(firestore: FakeFirebaseFirestore());
}

Widget _host(Widget home) => MaterialApp(
      theme:
          ThemeData(useMaterial3: true, splashFactory: NoSplash.splashFactory),
      home: home,
    );

Future<void> _seedPlan(
  FakeFirebaseFirestore firestore,
  ReadingPlanService planService, {
  required DateTime now,
}) async {
  const plan = ReadingPlan(
    id: 'p1',
    title: 'Test Plan',
    description: 'Desc',
    durationDays: 30,
    tags: [],
    schedule: [
      ReadingPlanDay(day: 1, readings: ['Genesis 1']),
      ReadingPlanDay(day: 2, readings: ['Genesis 2']),
    ],
  );
  await firestore.collection('custom_plans').doc('p1').set({
    ...plan.toJson(),
    'userId': 'u1',
  });
  await planService.startPlan('u1', 'p1', startDate: now);
}

/// Pumps Home for u1 and dismisses the auto-opened check-in.
Future<void> _pumpHome(
  WidgetTester tester,
  FakeFirebaseFirestore firestore, {
  ReadingPlanService? planService,
  GroupService? groupService,
}) async {
  await tester.pumpWidget(
    _host(
      HomePage(
        firestore: firestore,
        auth: MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true),
        vibrationService: const VibrationService(),
        bibleProgressService: _StubBibleProgressService(),
        readingPlanService: planService,
        groupService: groupService,
        userPreferencesService: UserPreferencesService(firestore: firestore),
        dateProvider: DateTime.now,
        enableDriftAnimation: false,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (find.bySemanticsLabel('Dismiss check-in').evaluate().isNotEmpty) {
    await tester.tap(find.bySemanticsLabel('Dismiss check-in'));
    await tester.pumpAndSettle();
  }
}

/// Seeds the two-day plan so its dates ended 10 days ago with day 1 read —
/// the "Plan ended" state, one reading left.
Future<void> _seedEndedPlan(
  FakeFirebaseFirestore firestore,
  ReadingPlanService planService,
) async {
  await _seedPlan(
    firestore,
    planService,
    now: DateTime.now().subtract(const Duration(days: 10)),
  );
  await _planProgressRef(firestore).update({
    'completedDays': [1],
  });
}

DocumentReference<Map<String, dynamic>> _planProgressRef(
  FakeFirebaseFirestore firestore,
) =>
    firestore
        .collection('users')
        .doc('u1')
        .collection('plan_progress')
        .doc('p1');

/// A Shared plan u1 reads as a member whose two readings ended 10 days ago,
/// the first one read — "Ended · 1 reading left" on Home.
Future<String> _seedEndedSharedPlan(
  FakeFirebaseFirestore firestore,
  GroupService groupService, {
  bool finished = false,
}) async {
  final groupId = await groupService.createGroup(
    ownerUid: 'naomi',
    name: 'Jeremiah Plan',
  );
  await firestore
      .collection('groups')
      .doc(groupId)
      .collection('members')
      .doc('u1')
      .set({
    'uid': 'u1',
    'role': 'member',
    if (finished) 'finishedAt': Timestamp.now(),
  });
  final today = DateTime.now();
  final first = DateTime(today.year, today.month, today.day - 10);
  final second = DateTime(today.year, today.month, today.day - 9);
  await groupService.updateSchedule(
    groupId: groupId,
    schedule: GroupSchedule(date: first, chapters: const ['Jer 1']),
  );
  await groupService.updateSchedule(
    groupId: groupId,
    schedule: GroupSchedule(date: second, chapters: const ['Jer 2']),
  );
  await firestore
      .collection('groups')
      .doc(groupId)
      .collection('progress')
      .doc(GroupService.dateId(first))
      .collection('entries')
      .doc('u1')
      .set({
    'groupId': groupId,
    'uid': 'u1',
    'dateId': GroupService.dateId(first),
    'count': 1,
    'done': true,
  });
  return groupId;
}

/// Adds a third Group reading (Jer 3, also past) to the ended Shared plan,
/// then stores the reader's Adjust pace: their unread readings now fall
/// today (Jer 2) and tomorrow (Jer 3), in their own overlay only.
Future<void> _seedPaceOverlayToToday(
  FakeFirebaseFirestore firestore,
  GroupService groupService,
  String groupId,
) async {
  final today = DateTime.now();
  await groupService.updateSchedule(
    groupId: groupId,
    schedule: GroupSchedule(
      date: DateTime(today.year, today.month, today.day - 8),
      chapters: const ['Jer 3'],
    ),
  );
  await PlanPaceService(firestore: firestore).applySharedPlanOverlay(
    uid: 'u1',
    groupId: groupId,
    adjusted: [
      GroupSchedule(
        date: DateTime(today.year, today.month, today.day - 10),
        chapters: const ['Jer 1'],
      ),
      GroupSchedule(
        date: DateTime(today.year, today.month, today.day),
        chapters: const ['Jer 2'],
      ),
      GroupSchedule(
        date: DateTime(today.year, today.month, today.day + 1),
        chapters: const ['Jer 3'],
      ),
    ],
  );
}

/// A Shared plan u1 is on track with: Jer 1 read yesterday, Jer 2 tomorrow.
/// With [ownPace] those are the reader's own overlay dates and the Group's
/// schedule ended 9 days ago; without it they are the Group's dates.
Future<void> _seedOnTrackSharedPlan(
  FakeFirebaseFirestore firestore,
  GroupService groupService, {
  required bool ownPace,
}) async {
  final groupId = await groupService.createGroup(
    ownerUid: 'naomi',
    name: 'Jeremiah Plan',
  );
  await firestore
      .collection('groups')
      .doc(groupId)
      .collection('members')
      .doc('u1')
      .set({'uid': 'u1', 'role': 'member'});
  final today = DateTime.now();
  DateTime day(int offset) =>
      DateTime(today.year, today.month, today.day + offset);
  final own = [
    GroupSchedule(date: day(-1), chapters: const ['Jer 1']),
    GroupSchedule(date: day(1), chapters: const ['Jer 2']),
  ];
  final groupSchedule = ownPace
      ? [
          GroupSchedule(date: day(-10), chapters: const ['Jer 1']),
          GroupSchedule(date: day(-9), chapters: const ['Jer 2']),
        ]
      : own;
  for (final s in groupSchedule) {
    await groupService.updateSchedule(groupId: groupId, schedule: s);
  }
  if (ownPace) {
    await PlanPaceService(firestore: firestore).applySharedPlanOverlay(
      uid: 'u1',
      groupId: groupId,
      adjusted: own,
    );
  }
  final readId = GroupService.dateId(day(-1));
  await firestore
      .collection('groups')
      .doc(groupId)
      .collection('progress')
      .doc(readId)
      .collection('entries')
      .doc('u1')
      .set({
    'groupId': groupId,
    'uid': 'u1',
    'dateId': readId,
    'count': 1,
    'done': true,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
    setupLottieHttpOverrides();
  });
  tearDownAll(resetHttpOverrides);

  testWidgets(
    'no active plan: habit hero shown, no "Today’s reading" card (#723)',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1'),
        signedIn: true,
      );

      await tester.pumpWidget(
        _host(
          HomePage(
            firestore: firestore,
            auth: auth,
            vibrationService: const VibrationService(),
            bibleProgressService: _StubBibleProgressService(),
            dateProvider: DateTime.now,
            enableDriftAnimation: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Auto-opens CheckInPage.
      expect(find.text('Did you read today?'), findsOneWidget);
      expect(find.text('I READ'), findsOneWidget);

      // Dismiss CheckInPage back to Home
      await tester.tap(find.bySemanticsLabel('Dismiss check-in'));
      await tester.pumpAndSettle();

      // Nothing prescriptive: no plan reading card.
      expect(find.text('Today’s reading'), findsNothing);
      expect(find.text('Mark as read'), findsNothing);
    },
  );

  testWidgets(
    'active plan: habit check-in AND a separate "Today’s reading" card (#722)',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1'),
        signedIn: true,
      );
      final planService = ReadingPlanService(firestore: firestore);
      await _seedPlan(firestore, planService, now: DateTime.now());

      await tester.pumpWidget(
        _host(
          HomePage(
            firestore: firestore,
            auth: auth,
            vibrationService: const VibrationService(),
            bibleProgressService: _StubBibleProgressService(),
            readingPlanService: planService,
            dateProvider: DateTime.now,
            enableDriftAnimation: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Auto-opens CheckInPage. Dismiss to view Home page.
      expect(find.text('Did you read today?'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Dismiss check-in'));
      await tester.pumpAndSettle();

      // Plus a distinct plan reading card.
      expect(find.text('Today’s reading'), findsOneWidget);
      expect(find.text('Genesis 1'), findsOneWidget);
      expect(find.text('Mark as read'), findsOneWidget);
    },
  );

  testWidgets('read state + active plan fits a phone viewport (no overflow)', (
    tester,
  ) async {
    // Default 800x600 test surface — the size at which CI caught a 20px
    // overflow before the SliverToBoxAdapter fix.
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    final planService = ReadingPlanService(firestore: firestore);
    await _seedPlan(firestore, planService, now: DateTime.now());

    // Already showed up today.
    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    await firestore
        .collection('users')
        .doc('u1')
        .collection('reading')
        .doc(dateKey)
        .set({'read': true});
    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({
      'streak': 5,
      'totalReadDays': 5,
      'pastWeekReadDates': [dateKey],
    });

    await tester.pumpWidget(
      _host(
        HomePage(
          firestore: firestore,
          auth: auth,
          vibrationService: const VibrationService(),
          bibleProgressService: _StubBibleProgressService(),
          readingPlanService: planService,
          dateProvider: DateTime.now,
          enableDriftAnimation: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Marked SunMark header button, plan reading card and the consistency glimpse all
    // coexist…
    expect(
      find.bySemanticsLabel('You read today — open check-in'),
      findsOneWidget,
    );
    expect(find.text('Today’s reading'), findsOneWidget);
    expect(find.text('Here 5 days this season'), findsOneWidget);
    // …without a layout overflow.
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'plan card mark advances the plan and asks the coupling question once',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1'),
        signedIn: true,
      );
      final planService = ReadingPlanService(firestore: firestore);
      await _seedPlan(firestore, planService, now: DateTime.now());

      await tester.pumpWidget(
        _host(
          HomePage(
            firestore: firestore,
            auth: auth,
            vibrationService: const VibrationService(),
            bibleProgressService: _StubBibleProgressService(),
            readingPlanService: planService,
            userPreferencesService: UserPreferencesService(
              firestore: firestore,
            ),
            dateProvider: DateTime.now,
            enableDriftAnimation: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (find.bySemanticsLabel('Dismiss check-in').evaluate().isNotEmpty) {
        await tester.tap(find.bySemanticsLabel('Dismiss check-in'));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('Mark as read'));
      await tester.pumpAndSettle();

      // First completion shows the one-time coupling prompt (SyncSheet).
      expect(find.text('Keep them separate'), findsOneWidget);
      await tester.tap(find.text('Keep them separate'));
      await tester.pumpAndSettle();

      // The plan day was recorded.
      final progressDoc = await firestore
          .collection('users')
          .doc('u1')
          .collection('plan_progress')
          .doc('p1')
          .get();
      final progress = UserPlanProgress.fromFirestore(progressDoc);
      expect(progress.completedDays, contains(1));

      // The habit today was recorded in Firestore.
      final today = DateTime.now();
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final habitDoc = await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc(dateKey)
          .get();
      expect(habitDoc.exists, isFalse);

      // The card now reflects the read state, non-interactively (design
      // parity: no standing undo-by-retap — only the just-shown snackbar's
      // Undo can reverse this).
      expect(find.text('Read · Genesis 1'), findsOneWidget);
    },
  );

  testWidgets(
    'plan card mark with coupling already linked marks the daily habit too',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1'),
        signedIn: true,
      );
      final planService = ReadingPlanService(firestore: firestore);
      await _seedPlan(firestore, planService, now: DateTime.now());

      final prefsService = UserPreferencesService(firestore: firestore);
      await prefsService.updatePreferences(
        'u1',
        const UserPreferences(autoMarkPlanRead: true, syncPromptAnswered: true),
      );

      await tester.pumpWidget(
        _host(
          HomePage(
            firestore: firestore,
            auth: auth,
            vibrationService: const VibrationService(),
            bibleProgressService: _StubBibleProgressService(),
            readingPlanService: planService,
            userPreferencesService: prefsService,
            dateProvider: DateTime.now,
            enableDriftAnimation: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (find.bySemanticsLabel('Dismiss check-in').evaluate().isNotEmpty) {
        await tester.tap(find.bySemanticsLabel('Dismiss check-in'));
        await tester.pumpAndSettle();
      }

      // Coupling is already linked, so no SyncSheet should appear.
      await tester.tap(find.text('Mark as read'));
      await tester.pumpAndSettle();
      expect(find.text('Keep them separate'), findsNothing);

      // The habit was recorded in Firestore...
      final today = DateTime.now();
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final habitDoc = await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc(dateKey)
          .get();
      expect(habitDoc.data()?['read'], isTrue);

      // ...and the SunMark in header reflects it with marked state.
      expect(
        find.bySemanticsLabel('You read today — open check-in'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'group card mark, first-time "Yes" choice, marks the daily habit too',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1'),
        signedIn: true,
      );
      final groupService = GroupService(firestore: firestore);

      final groupId = await groupService.createGroup(
        ownerUid: 'u1',
        name: 'Test Group',
      );
      final today = DateTime.now();
      await groupService.updateSchedule(
        groupId: groupId,
        schedule: GroupSchedule(date: today, chapters: const ['John 1']),
      );

      await tester.pumpWidget(
        _host(
          HomePage(
            firestore: firestore,
            auth: auth,
            vibrationService: const VibrationService(),
            bibleProgressService: _StubBibleProgressService(),
            groupService: groupService,
            userPreferencesService: UserPreferencesService(
              firestore: firestore,
            ),
            dateProvider: DateTime.now,
            enableDriftAnimation: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (find.bySemanticsLabel('Dismiss check-in').evaluate().isNotEmpty) {
        await tester.tap(find.bySemanticsLabel('Dismiss check-in'));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('Read with your group'));
      await tester.pumpAndSettle();

      // First completion shows the one-time coupling prompt; choose "Yes".
      expect(find.text('Yes, count it as showing up'), findsOneWidget);
      await tester.tap(find.text('Yes, count it as showing up'));
      await tester.pumpAndSettle();

      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final habitDoc = await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc(dateKey)
          .get();
      expect(habitDoc.data()?['read'], isTrue);
      expect(
        find.bySemanticsLabel('You read today — open check-in'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'group card appears for a member who does not own the group (#779)',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1'),
        signedIn: true,
      );
      final groupService = GroupService(firestore: firestore);

      // Regression for #779: u1 is only a member here. groupsForUser() used
      // to emit an empty list first when the owner query resolved before the
      // member query, and HomePage sampled exactly that event, hiding the
      // group from Home.
      final groupId = await groupService.createGroup(
        ownerUid: 'naomi',
        name: 'Test Group',
      );
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc('u1')
          .set({'uid': 'u1', 'role': 'member'});
      final today = DateTime.now();
      await groupService.updateSchedule(
        groupId: groupId,
        schedule: GroupSchedule(date: today, chapters: const ['John 1']),
      );

      await tester.pumpWidget(
        _host(
          HomePage(
            firestore: firestore,
            auth: auth,
            vibrationService: const VibrationService(),
            bibleProgressService: _StubBibleProgressService(),
            groupService: groupService,
            userPreferencesService: UserPreferencesService(
              firestore: firestore,
            ),
            dateProvider: DateTime.now,
            enableDriftAnimation: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (find.bySemanticsLabel('Dismiss check-in').evaluate().isNotEmpty) {
        await tester.tap(find.bySemanticsLabel('Dismiss check-in'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Test Group · together'), findsOneWidget);
    },
  );
  group('Plan ended card (ADR-0010)', () {
    testWidgets(
      'shows Keep reading and Adjust pace side by side, plus a quiet Finish '
      'plan, with no Reschedule',
      (tester) async {
        final firestore = FakeFirebaseFirestore();
        final planService = ReadingPlanService(firestore: firestore);
        await _seedEndedPlan(firestore, planService);

        await _pumpHome(tester, firestore, planService: planService);

        expect(find.text('Plan ended · finish at your pace'), findsOneWidget);
        expect(find.text('Keep reading'), findsOneWidget);
        expect(find.text('Adjust pace'), findsOneWidget);
        expect(find.text('Finish plan'), findsOneWidget);
        expect(find.text('Reschedule'), findsNothing);

        // Equal halves, each label on a single line.
        final keep =
            tester.getSize(find.widgetWithText(FilledButton, 'Keep reading'));
        final adjust =
            tester.getSize(find.widgetWithText(OutlinedButton, 'Adjust pace'));
        expect(keep.width, adjust.width);
        expect(
          tester.getSize(find.text('Keep reading')).height,
          lessThan(24),
        );
      },
    );

    testWidgets('Adjust pace opens the Adjust pace flow', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final planService = ReadingPlanService(firestore: firestore);
      await _seedEndedPlan(firestore, planService);

      await _pumpHome(tester, firestore, planService: planService);
      await tester.tap(find.text('Adjust pace'));
      await tester.pumpAndSettle();

      expect(find.byType(AdjustPacePage), findsOneWidget);
      expect(find.text('Stretch it out'), findsOneWidget);
    });

    testWidgets(
      'Finish plan removes the plan from Home without marking readings, and '
      'Undo brings it back',
      (tester) async {
        final firestore = FakeFirebaseFirestore();
        final planService = ReadingPlanService(firestore: firestore);
        await _seedEndedPlan(firestore, planService);

        await _pumpHome(tester, firestore, planService: planService);
        await tester.tap(find.text('Finish plan'));
        await tester.pumpAndSettle();

        expect(find.text('Plan ended · finish at your pace'), findsNothing);
        expect(find.text('Finished "Test Plan"'), findsOneWidget);
        final finished = await _planProgressRef(firestore).get();
        expect(finished.data()?['finishedAt'], isNotNull);
        expect(finished.data()?['completedDays'], [1]);

        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();

        expect(
          (await _planProgressRef(firestore).get()).data()?['finishedAt'],
          isNull,
        );
        expect(find.text('Plan ended · finish at your pace'), findsOneWidget);
      },
    );

    testWidgets('a finished solo plan does not appear on Home', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();
      final planService = ReadingPlanService(firestore: firestore);
      await _seedEndedPlan(firestore, planService);
      await planService.finishPlan('u1', 'p1');

      await _pumpHome(tester, firestore, planService: planService);

      expect(find.text('Plan ended · finish at your pace'), findsNothing);
      expect(find.text('Test Plan'), findsNothing);
    });

    testWidgets(
      'an ended Shared plan offers Finish plan, which closes only the '
      "reader's own participation",
      (tester) async {
        final firestore = FakeFirebaseFirestore();
        final groupService = GroupService(firestore: firestore);
        final groupId = await _seedEndedSharedPlan(firestore, groupService);

        await _pumpHome(tester, firestore, groupService: groupService);

        expect(find.text('Plan ended · finish at your pace'), findsOneWidget);
        expect(find.text('Keep reading'), findsOneWidget);
        expect(find.text('Finish plan'), findsOneWidget);

        await tester.tap(find.text('Finish plan'));
        await tester.pumpAndSettle();

        expect(find.text('Plan ended · finish at your pace'), findsNothing);
        final member = await firestore
            .collection('groups')
            .doc(groupId)
            .collection('members')
            .doc('u1')
            .get();
        expect(member.data()?['finishedAt'], isNotNull);
        expect(member.data()?['role'], 'member');
      },
    );

    testWidgets(
      'an ended Shared plan shows Keep reading and Adjust pace side by side',
      (tester) async {
        final firestore = FakeFirebaseFirestore();
        final groupService = GroupService(firestore: firestore);
        await _seedEndedSharedPlan(firestore, groupService);

        await _pumpHome(tester, firestore, groupService: groupService);

        expect(find.text('Keep reading'), findsOneWidget);
        expect(find.text('Adjust pace'), findsOneWidget);
        expect(find.text('Finish plan'), findsOneWidget);
        expect(find.text('Reschedule'), findsNothing);

        // Equal halves, each label on a single line.
        final keep =
            tester.getSize(find.widgetWithText(FilledButton, 'Keep reading'));
        final adjust =
            tester.getSize(find.widgetWithText(OutlinedButton, 'Adjust pace'));
        expect(keep.width, adjust.width);
        expect(tester.getSize(find.text('Adjust pace')).height, lessThan(24));
      },
    );

    testWidgets(
      "Adjust pace on a Shared plan writes only the reader's own overlay",
      (tester) async {
        final firestore = FakeFirebaseFirestore();
        final groupService = GroupService(firestore: firestore);
        final groupId = await _seedEndedSharedPlan(firestore, groupService);
        final scheduleRef =
            firestore.collection('groups').doc(groupId).collection('schedule');
        Future<Map<String, Object?>> scheduleSnapshot() async => {
              for (final doc in (await scheduleRef.get()).docs)
                doc.id: doc.data(),
            };
        final scheduleBefore = await scheduleSnapshot();

        await _pumpHome(tester, firestore, groupService: groupService);
        await tester.tap(find.text('Adjust pace'));
        await tester.pumpAndSettle();

        expect(find.byType(AdjustPacePage), findsOneWidget);
        expect(find.textContaining('only your own schedule'), findsOneWidget);

        await tester.tap(find.text('Stretch it out'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();

        expect(find.byType(AdjustPacePage), findsNothing);
        final overlay = await firestore
            .collection('users')
            .doc('u1')
            .collection('plan_pace')
            .doc(groupId)
            .get();
        expect(overlay.exists, isTrue);
        expect(overlay.data()?['groupId'], groupId);
        expect(overlay.data()?['days'], isNotEmpty);
        expect(await scheduleSnapshot(), scheduleBefore);
      },
    );

    testWidgets(
      "a Shared plan follows the reader's pace overlay, not the Group's dates",
      (tester) async {
        final firestore = FakeFirebaseFirestore();
        final groupService = GroupService(firestore: firestore);
        final groupId = await _seedEndedSharedPlan(firestore, groupService);
        await _seedPaceOverlayToToday(firestore, groupService, groupId);

        await _pumpHome(tester, firestore, groupService: groupService);

        expect(find.text('Plan ended · finish at your pace'), findsNothing);
        expect(
          find.widgetWithText(FilledButton, 'Read with your group'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      "a reading done on the reader's own date shows as read, though the "
      'Group has nothing scheduled that day',
      (tester) async {
        final firestore = FakeFirebaseFirestore();
        final groupService = GroupService(firestore: firestore);
        final groupId = await _seedEndedSharedPlan(firestore, groupService);
        await _seedPaceOverlayToToday(firestore, groupService, groupId);
        final todayId = GroupService.dateId(DateTime.now());
        await firestore
            .collection('groups')
            .doc(groupId)
            .collection('progress')
            .doc(todayId)
            .collection('entries')
            .doc('u1')
            .set({
          'groupId': groupId,
          'uid': 'u1',
          'dateId': todayId,
          'count': 1,
          'done': true,
        });

        await _pumpHome(tester, firestore, groupService: groupService);

        expect(find.text('Read with your group'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, 'Read with your group'),
          findsNothing,
        );
      },
    );

    testWidgets('a finished Shared plan does not appear on Home', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();
      final groupService = GroupService(firestore: firestore);
      await _seedEndedSharedPlan(firestore, groupService, finished: true);

      await _pumpHome(tester, firestore, groupService: groupService);

      expect(find.text('Plan ended · finish at your pace'), findsNothing);
      expect(find.text('Jeremiah Plan · together'), findsNothing);
    });

    testWidgets('the compact Shared plan row reads "Ended · N readings left"', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();
      final planService = ReadingPlanService(firestore: firestore);
      final groupService = GroupService(firestore: firestore);
      // A running plan is the hero; the ended Shared plan folds into a row.
      await _seedPlan(firestore, planService, now: DateTime.now());
      await _seedEndedSharedPlan(firestore, groupService);

      await _pumpHome(
        tester,
        firestore,
        planService: planService,
        groupService: groupService,
      );

      expect(find.text('Jeremiah Plan · together'), findsOneWidget);
      expect(find.text('Ended · 1 reading left'), findsOneWidget);
      expect(find.textContaining('Finish ·'), findsNothing);
    });
    testWidgets(
      'an on-track Shared plan on the Group schedule reads "In step with '
      'your group"',
      (tester) async {
        final firestore = FakeFirebaseFirestore();
        final groupService = GroupService(firestore: firestore);
        await _seedOnTrackSharedPlan(firestore, groupService, ownPace: false);

        await _pumpHome(tester, firestore, groupService: groupService);

        expect(find.text('In step with your group'), findsOneWidget);
        expect(find.text("You're on track"), findsNothing);
      },
    );

    testWidgets(
      "an on-track Shared plan on the reader's own pace reads \"You're on "
      'track"',
      (tester) async {
        final firestore = FakeFirebaseFirestore();
        final groupService = GroupService(firestore: firestore);
        await _seedOnTrackSharedPlan(firestore, groupService, ownPace: true);

        await _pumpHome(tester, firestore, groupService: groupService);

        expect(find.text("You're on track"), findsOneWidget);
        expect(find.text('In step with your group'), findsNothing);
      },
    );
  });
}

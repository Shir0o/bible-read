import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/models/user_preferences.dart';
import 'package:bible_read/services/group_collections.dart';
import 'package:bible_read/services/habit_lifecycle_service.dart';
import 'package:bible_read/services/read_log_service.dart';
import 'package:bible_read/services/reading_plan_service.dart';
import 'package:bible_read/services/reading_status_service.dart';
import 'package:bible_read/services/user_preferences_service.dart';
import 'package:bible_read/widgets/burst_undo_controller.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late MockUser user;
  late MockFirebaseAuth auth;
  late HabitLifecycleService service;
  late ReadingStatusService statusService;
  late UserPreferencesService prefsService;
  late ReadingPlanService planService;

  // The real calendar day: maybeCoupleHabit and burst paths mark
  // DateTime.now(), so a fixed date breaks once the clock passes it.
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final todayKey = ReadLogService.dateKeyFor(today);

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    user = MockUser(uid: 'u1', displayName: 'Reader', email: 'reader@test.com');
    auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    statusService = ReadingStatusService(
      firestore: firestore,
      auth: auth,
      nowProvider: () => today,
    );
    prefsService = UserPreferencesService(firestore: firestore);
    planService = ReadingPlanService(firestore: firestore);
    service = HabitLifecycleService(
      firestore: firestore,
      readingStatusService: statusService,
      preferencesService: prefsService,
      planService: planService,
    );
  });

  group('Showing up directly (presence)', () {
    test('hasShownUp reflects reading document existence and state', () async {
      expect(await service.hasShownUp('u1', date: today), isFalse);

      final docRef = firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc(todayKey);

      await docRef.set({'read': true});
      expect(await service.hasShownUp('u1', date: today), isTrue);

      await docRef.set({'read': false});
      expect(await service.hasShownUp('u1', date: today), isFalse);
    });

    test(
        'showUp records presence in reading doc, feed, updates streak, and invalidates cache',
        () async {
      // Setup a group for u1
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'Group 1'});
      await groupRef
          .collection(GroupCollections.members)
          .doc('u1')
          .set({'uid': 'u1'});

      // Stale streak baseline
      await firestore
          .collection('users')
          .doc('u1')
          .collection('summary')
          .doc('data')
          .set({'streak': 0, 'totalReadDays': 0});

      await service.showUp(user, date: today);

      // Verify user reading document
      final readDoc = await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc(todayKey)
          .get();
      expect(readDoc.exists, isTrue);
      expect(readDoc.data()?['read'], isTrue);

      // Verify group read_log entry
      final feedDoc = await groupRef
          .collection('read_log')
          .doc(todayKey)
          .collection('entries')
          .doc('u1')
          .get();
      expect(feedDoc.exists, isTrue);
      expect(feedDoc.data()?['uid'], 'u1');

      // Verify summary streak updated
      final summaryDoc = await firestore
          .collection('users')
          .doc('u1')
          .collection('summary')
          .doc('data')
          .get();
      expect(summaryDoc.data()?['streak'], 1);
      expect(summaryDoc.data()?['totalReadDays'], 1);
    });

    test(
        'clearShowingUp un-marks reading doc, deletes group entry, and updates summary',
        () async {
      final groupRef = firestore.collection(GroupCollections.groups).doc('g1');
      await groupRef.set({'name': 'Group 1'});
      await groupRef
          .collection(GroupCollections.members)
          .doc('u1')
          .set({'uid': 'u1'});

      await service.showUp(user, date: today);
      expect(await service.hasShownUp('u1', date: today), isTrue);

      await service.clearShowingUp(user, date: today);

      final readDoc = await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc(todayKey)
          .get();
      expect(readDoc.data()?['read'], isFalse);

      final feedDoc = await groupRef
          .collection('read_log')
          .doc(todayKey)
          .collection('entries')
          .doc('u1')
          .get();
      expect(feedDoc.exists, isFalse);

      final summaryDoc = await firestore
          .collection('users')
          .doc('u1')
          .collection('summary')
          .doc('data')
          .get();
      expect(summaryDoc.data()?['streak'], 0);
    });
  });

  group('Habit coupling for readings', () {
    testWidgets(
        'maybeCoupleHabit with unanswered prompt presents SyncSheet and links when confirmed',
        (tester) async {
      late BuildContext buildCtx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          buildCtx = c;
          return const SizedBox();
        }),
      ));

      final future = service.maybeCoupleHabit(context: buildCtx, user: user);
      await tester.pumpAndSettle();

      expect(find.text("You finished today's reading"), findsOneWidget);

      await tester.tap(find.text('Yes, count it as showing up'));
      await tester.pumpAndSettle();

      final coupled = await future;
      expect(coupled, isTrue);

      final prefs = await prefsService.fetchPreferences('u1');
      expect(prefs.syncPromptAnswered, isTrue);
      expect(prefs.autoMarkPlanRead, isTrue);
      expect(await service.hasShownUp('u1', date: today), isTrue);
    });

    testWidgets(
        'maybeCoupleHabit with unanswered prompt saves choice and skips habit when declined',
        (tester) async {
      late BuildContext buildCtx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          buildCtx = c;
          return const SizedBox();
        }),
      ));

      final future = service.maybeCoupleHabit(context: buildCtx, user: user);
      await tester.pumpAndSettle();

      expect(find.text("You finished today's reading"), findsOneWidget);

      await tester.tap(find.text('Keep them separate'));
      await tester.pumpAndSettle();

      final coupled = await future;
      expect(coupled, isFalse);

      final prefs = await prefsService.fetchPreferences('u1');
      expect(prefs.syncPromptAnswered, isTrue);
      expect(prefs.autoMarkPlanRead, isFalse);
      expect(await service.hasShownUp('u1', date: today), isFalse);
    });

    testWidgets(
        'maybeCoupleHabit when linked records habit directly without prompt',
        (tester) async {
      await prefsService.updatePreferences(
        'u1',
        const UserPreferences(autoMarkPlanRead: true, syncPromptAnswered: true),
      );

      late BuildContext buildCtx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          buildCtx = c;
          return const SizedBox();
        }),
      ));

      final coupled =
          await service.maybeCoupleHabit(context: buildCtx, user: user);
      await tester.pumpAndSettle();

      expect(coupled, isTrue);
      expect(find.text("You finished today's reading"), findsNothing);
      expect(await service.hasShownUp('u1', date: today), isTrue);
    });

    testWidgets('maybeCoupleHabit when unlinked does nothing', (tester) async {
      await prefsService.updatePreferences(
        'u1',
        const UserPreferences(
            autoMarkPlanRead: false, syncPromptAnswered: true),
      );

      late BuildContext buildCtx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          buildCtx = c;
          return const SizedBox();
        }),
      ));

      final coupled =
          await service.maybeCoupleHabit(context: buildCtx, user: user);
      expect(coupled, isFalse);
      expect(await service.hasShownUp('u1', date: today), isFalse);
    });

    testWidgets('completePlanDay marks plan, credits lap, and couples habit',
        (tester) async {
      const plan = ReadingPlan(
        id: 'p1',
        title: 'Plan 1',
        description: 'Desc',
        durationDays: 3,
        tags: [],
        schedule: [
          ReadingPlanDay(day: 1, readings: ['Gen 1']),
        ],
      );

      await firestore.collection('custom_plans').doc('p1').set({
        ...plan.toJson(),
        'userId': 'u1',
      });
      await planService.startPlan('u1', 'p1', startDate: today);
      await prefsService.updatePreferences(
        'u1',
        const UserPreferences(autoMarkPlanRead: true, syncPromptAnswered: true),
      );

      late BuildContext buildCtx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          buildCtx = c;
          return const SizedBox();
        }),
      ));

      final coupled = await tester.runAsync(
        () => service.completePlanDay(
          context: buildCtx,
          user: user,
          planId: 'p1',
          day: 1,
        ),
      );

      expect(coupled, isTrue);
      final progressDoc = await firestore
          .collection('users')
          .doc('u1')
          .collection('plan_progress')
          .doc('p1')
          .get();
      expect(progressDoc.data()?['completedDays'], contains(1));
      expect(await service.hasShownUp('u1', date: today), isTrue);
    });
  });

  group('Burst-aware habit management', () {
    testWidgets('burst undo reverts habit when burst caused it',
        (tester) async {
      await prefsService.updatePreferences(
        'u1',
        const UserPreferences(autoMarkPlanRead: true, syncPromptAnswered: true),
      );

      final burstUndo = BurstUndoController();
      addTearDown(burstUndo.dispose);

      late BuildContext buildCtx;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (c) {
            buildCtx = c;
            return const SizedBox();
          }),
        ),
      ));

      var callerUndoRan = false;
      final coupled = await service.coupleWithBurst(
        context: buildCtx,
        user: user,
        burstController: burstUndo,
        onUndo: () => callerUndoRan = true,
      );
      expect(coupled, isTrue);
      expect(burstUndo.count, 1);
      expect(await service.hasShownUp('u1', date: today), isTrue);

      // Pump entrance animation until SnackBar is fully settled and not transitioning
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      // Tap Undo on SnackBar
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await service.lastBurstUndoFuture;
      await tester.pump();

      expect(callerUndoRan, isTrue);
      expect(burstUndo.count, 0);
      expect(await service.hasShownUp('u1', date: today), isFalse);
    });

    testWidgets(
        'burst undo does NOT revert habit if habit was already recorded before burst',
        (tester) async {
      await prefsService.updatePreferences(
        'u1',
        const UserPreferences(autoMarkPlanRead: true, syncPromptAnswered: true),
      );

      // Pre-record habit before burst begins
      await service.showUp(user, date: today);
      expect(await service.hasShownUp('u1', date: today), isTrue);

      final burstUndo = BurstUndoController();
      addTearDown(burstUndo.dispose);

      late BuildContext buildCtx;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (c) {
            buildCtx = c;
            return const SizedBox();
          }),
        ),
      ));

      var callerUndoRan = false;
      await service.coupleWithBurst(
        context: buildCtx,
        user: user,
        burstController: burstUndo,
        onUndo: () => callerUndoRan = true,
      );
      expect(burstUndo.count, 1);

      // Pump entrance animation until SnackBar is fully settled and not transitioning
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      // Tap Undo on SnackBar
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await service.lastBurstUndoFuture;
      await tester.pump();

      expect(callerUndoRan, isTrue);
      expect(burstUndo.count, 0);
      // Pre-existing habit is preserved!
      expect(await service.hasShownUp('u1', date: today), isTrue);
    });

    testWidgets('multiple marks in burst revert habit exactly once on undo',
        (tester) async {
      await prefsService.updatePreferences(
        'u1',
        const UserPreferences(autoMarkPlanRead: true, syncPromptAnswered: true),
      );

      final burstUndo = BurstUndoController();
      addTearDown(burstUndo.dispose);

      late BuildContext buildCtx;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (c) {
            buildCtx = c;
            return const SizedBox();
          }),
        ),
      ));

      final undosCalled = <int>[];

      // Mark 1
      await service.coupleWithBurst(
        context: buildCtx,
        user: user,
        burstController: burstUndo,
        onUndo: () => undosCalled.add(1),
      );
      await tester.pump();

      // Mark 2
      await service.coupleWithBurst(
        context: buildCtx,
        user: user,
        burstController: burstUndo,
        onUndo: () => undosCalled.add(2),
      );
      await tester.pump();

      // Mark 3
      await service.coupleWithBurst(
        context: buildCtx,
        user: user,
        burstController: burstUndo,
        onUndo: () => undosCalled.add(3),
      );

      expect(burstUndo.count, 3);
      expect(await service.hasShownUp('u1', date: today), isTrue);

      // Pump entrance animation until SnackBar is fully settled and not transitioning
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      // Undo the whole burst
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await service.lastBurstUndoFuture;
      await tester.pump();

      // LIFO undo order
      expect(undosCalled, [3, 2, 1]);
      expect(burstUndo.count, 0);
      expect(await service.hasShownUp('u1', date: today), isFalse);
    });

    testWidgets(
        'month marking with registerBurstMark and coupleMonthWithBurst reverts habit on undo',
        (tester) async {
      await prefsService.updatePreferences(
        'u1',
        const UserPreferences(autoMarkPlanRead: true, syncPromptAnswered: true),
      );

      final burstUndo = BurstUndoController();
      addTearDown(burstUndo.dispose);

      late BuildContext buildCtx;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (c) {
            buildCtx = c;
            return const SizedBox();
          }),
        ),
      ));

      final undos = <int>[];
      for (final day in [1, 2, 3]) {
        await service.registerBurstMark(
          context: buildCtx,
          user: user,
          burstController: burstUndo,
          onUndo: () => undos.add(day),
        );
        await tester.pump();
      }

      await service.coupleMonthWithBurst(
        context: buildCtx,
        user: user,
        burstController: burstUndo,
      );

      expect(burstUndo.count, 3);
      expect(await service.hasShownUp('u1', date: today), isTrue);

      // Pump entrance animation until SnackBar is fully settled and not transitioning
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      await tester.tap(find.text('Undo'));
      await tester.pump();
      await service.lastBurstUndoFuture;
      await tester.pump();

      expect(undos, [3, 2, 1]);
      expect(burstUndo.count, 0);
      expect(await service.hasShownUp('u1', date: today), isFalse);
    });
  });
}

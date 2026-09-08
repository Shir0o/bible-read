// Page seam for the trash and archive hubs (#776): the Recently Deleted hub
// shows countdowns, restores to the prior state, purges permanently, and
// empties; the PlansHub archives a plan and reaches both hubs.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/pages/recently_deleted_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/reading_plan_service.dart';
import 'package:bible_read/services/user_preferences_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/widgets/journey/plans_hub.dart';

class _StubVibrationService extends VibrationService {
  const _StubVibrationService();
  @override
  Future<void> lightImpact() async {}
  @override
  Future<void> mediumImpact() async {}
}

const _plan = ReadingPlan(
  id: 'p1',
  title: 'Morning Light',
  description: 'A gentle daily reading',
  durationDays: 2,
  tags: [],
  schedule: [
    ReadingPlanDay(day: 1, readings: ['Gen 1']),
    ReadingPlanDay(day: 2, readings: ['Gen 2']),
  ],
);

void main() {
  group('RecentlyDeletedPage', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late ReadingPlanService planService;
    late GroupService groupService;
    late DateTime fixedNow;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
      planService = ReadingPlanService(firestore: firestore);
      groupService = GroupService(firestore: firestore);

      await firestore.collection('custom_plans').doc('p1').set({
        ..._plan.toJson(),
        'userId': 'u1',
      });
      await planService.startPlan('u1', 'p1', startDate: DateTime(2026, 9, 1));
      await planService.markDayComplete('u1', 'p1', 1);
      // Trashed 10 days ago: 20 days left of the 30.
      fixedNow = DateTime(2026, 9, 8, 12);
      await planService.softDeletePlan(
        'u1',
        'p1',
        now: fixedNow.subtract(const Duration(days: 10)),
      );
    });

    Future<void> pumpPage(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecentlyDeletedPage(
            firestore: firestore,
            auth: auth,
            groupService: groupService,
            readingPlanService: planService,
            vibrationService: const _StubVibrationService(),
            dateProvider: () => fixedNow,
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 1200));
    }

    testWidgets('shows the countdown of days left until purge', (tester) async {
      await pumpPage(tester);

      expect(find.text('Morning Light'), findsOneWidget);
      expect(find.text('20 days left'), findsOneWidget);
      expect(find.text('Empty Trash'), findsOneWidget);
    });

    testWidgets('restore returns the plan to its pre-deletion state',
        (tester) async {
      await pumpPage(tester);

      await tester.tap(find.byTooltip('Restore'));
      await tester.pumpAndSettle(const Duration(milliseconds: 1200));

      // It was active when trashed — it comes back active with its progress.
      final progress = await firestore
          .collection('users')
          .doc('u1')
          .collection('plan_progress')
          .doc('p1')
          .get();
      expect(progress.data()?['deletedAt'], isNull);
      expect(progress.data()?['isArchived'], isFalse);
      expect(progress.data()?['completedDays'], [1]);
      expect(find.text('20 days left'), findsNothing);
    });

    testWidgets('restore puts an archived-deleted plan back in the archive',
        (tester) async {
      await planService.restorePlan('u1', 'p1');
      await planService.archivePlan('u1', 'p1');
      await planService.softDeletePlan('u1', 'p1');
      await pumpPage(tester);

      await tester.tap(find.byTooltip('Restore'));
      await tester.pumpAndSettle(const Duration(milliseconds: 1200));

      final progress = await firestore
          .collection('users')
          .doc('u1')
          .collection('plan_progress')
          .doc('p1')
          .get();
      expect(progress.data()?['isArchived'], isTrue);
      expect(progress.data()?['deletedAt'], isNull);
    });

    testWidgets('delete permanently purges after a confirm dialog',
        (tester) async {
      await pumpPage(tester);

      await tester.tap(find.byTooltip('Delete permanently'));
      await tester.pumpAndSettle();
      expect(find.text('Delete "Morning Light"?'), findsOneWidget);
      await tester.tap(find.text('Delete Permanently'));
      await tester.pumpAndSettle(const Duration(milliseconds: 1200));

      final progress = await firestore
          .collection('users')
          .doc('u1')
          .collection('plan_progress')
          .doc('p1')
          .get();
      expect(progress.exists, isFalse);
      expect(find.text('Empty Trash'), findsNothing);
    });

    testWidgets('empty trash purges everything at once', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.text('Empty Trash'));
      await tester.pumpAndSettle();
      expect(find.text('Empty Trash?'), findsOneWidget);
      await tester.tap(find.text('Empty Trash').last);
      await tester.pumpAndSettle(const Duration(milliseconds: 1200));

      final progress = await firestore
          .collection('users')
          .doc('u1')
          .collection('plan_progress')
          .doc('p1')
          .get();
      expect(progress.exists, isFalse);
      expect(find.text('Morning Light'), findsNothing);
    });

    testWidgets('empty state shows when nothing is trashed', (tester) async {
      await planService.permanentlyDeletePlan('u1', 'p1');
      await pumpPage(tester);

      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.text('Empty Trash'), findsNothing);
    });
  });

  group('PlansHub archive and trash affordances', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late ReadingPlanService planService;
    late GroupService groupService;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
      planService = ReadingPlanService(firestore: firestore);
      groupService = GroupService(firestore: firestore);

      await firestore.collection('custom_plans').doc('p1').set({
        ..._plan.toJson(),
        'userId': 'u1',
      });
      await planService.startPlan('u1', 'p1', startDate: DateTime.now());
    });

    Future<void> pumpPage(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlansHub(
              firestore: firestore,
              auth: auth,
              groupService: groupService,
              readingPlanService: planService,
              userPreferencesService:
                  UserPreferencesService(firestore: firestore),
              vibrationService: const _StubVibrationService(),
              dateProvider: DateTime.now,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 1200));
    }

    testWidgets(
        'archiving a plan shows it in Archive with a trash action; '
        'trashing lands it in Recently Deleted with a countdown',
        (tester) async {
      await pumpPage(tester);

      // Leave = archive via the card's inline confirm.
      await tester.tap(find.byTooltip('Leave plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Leave plan'));
      await tester.pumpAndSettle(const Duration(milliseconds: 1200));
      expect(find.text('Archived'), findsOneWidget);

      // Move it to the trash from the archive row.
      await tester.tap(find.byTooltip('Delete plan'));
      await tester.pumpAndSettle();
      expect(find.text('Delete "Morning Light"?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle(const Duration(milliseconds: 1200));

      // Gone from the hub; the trash shortcut counts it.
      expect(find.text('Archived'), findsNothing);
      expect(find.text('Recently Deleted · 1 waiting'), findsOneWidget);
    });

    testWidgets('the trash shortcut opens the Recently Deleted hub',
        (tester) async {
      await planService.softDeletePlan('u1', 'p1');
      await pumpPage(tester);

      await tester.tap(find.text('Recently Deleted · 1 waiting'));
      await tester.pumpAndSettle(const Duration(milliseconds: 1200));

      expect(find.byType(RecentlyDeletedPage), findsOneWidget);
      expect(find.text('29 days left'), findsOneWidget);
    });
  });
}

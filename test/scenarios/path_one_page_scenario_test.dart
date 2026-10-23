// Slice 1 of the third-pass navigation (#981): Path is one page with three
// sections, Plans, Consistency and Read-throughs, each skeleton-first. The
// plan list sits under the header with no title of its own.
import 'package:bible_read/pages/bible_progress_page.dart';
import 'package:bible_read/pages/journey_page.dart';
import 'package:bible_read/pages/streak_history_page.dart';
import 'package:bible_read/widgets/skeleton.dart';
import 'package:bible_read/widgets/skeleton_loader.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/firebase_seeder.dart';
import '../helpers/pump_app.dart';
import '../helpers/stub_vibration_service.dart';

void main() {
  late MockFirebaseAuth auth;
  late FakeFirebaseFirestore firestore;
  final now = DateTime(2026, 10, 16, 9);

  setUp(() async {
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    firestore = FakeFirebaseFirestore();
    await FirebaseSeeder(firestore).seedUser(uid: 'u1');
  });

  Future<void> pumpPath(WidgetTester tester, {bool settle = true}) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpApp(
      JourneyPage(
        auth: auth,
        firestore: firestore,
        vibrationService: StubVibrationService(),
        dateProvider: () => now,
      ),
    );
    if (settle) await tester.pumpAndSettle(const Duration(milliseconds: 1200));
  }

  Future<void> seedSeason() => firestore.collection('seasons').doc('s1').set({
        'title': 'Advent Journey',
        'description': 'Walk toward the manger.',
        'startDate': Timestamp.fromDate(DateTime(2026, 10, 1)),
        'endDate': Timestamp.fromDate(DateTime(2026, 10, 20)),
      });

  testWidgets('shows exactly the three sections and no stat tiles or strip', (
    tester,
  ) async {
    await pumpPath(tester);

    expect(find.byKey(const Key('path-plans')), findsOneWidget);
    expect(find.text('Consistency'), findsOneWidget);
    expect(find.text('Read-throughs'), findsOneWidget);
    expect(find.text('Day streak'), findsNothing);
    expect(find.text('Shown up'), findsNothing);
    expect(find.text('Badges'), findsNothing);
    expect(find.text('Current streak'), findsOneWidget);
    expect(find.text('Shown up in October'), findsOneWidget);
  });

  testWidgets('every section shows a skeleton on the first frame', (
    tester,
  ) async {
    await pumpPath(tester, settle: false);

    for (final key in [
      'path-plans',
      'path-consistency',
      'path-read-throughs'
    ]) {
      final section = find.byKey(Key(key));
      expect(
        find.descendant(of: section, matching: find.byType(SkeletonLoader)),
        findsWidgets,
        reason: key,
      );
      expect(
        find.descendant(of: section, matching: find.byType(Skeleton)),
        findsWidgets,
        reason: key,
      );
    }
    // Titles stay visible while content loads.
    expect(find.text('Consistency'), findsOneWidget);
    expect(find.text('Read-throughs'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));
  });

  testWidgets('the Seasonal Challenge card lives on Today, not Path', (
    tester,
  ) async {
    await seedSeason();
    await pumpPath(tester);

    expect(find.text('Advent Journey'), findsNothing);
    expect(find.byKey(const Key('today-challenge-card')), findsNothing);
  });

  testWidgets(
      'streak and month figures head the card; tapping the calendar '
      'opens streak history', (tester) async {
    await firestore
        .collection('users')
        .doc('u1')
        .collection('summary')
        .doc('data')
        .set({'streak': 6});
    for (final key in ['2026-10-01', '2026-10-02']) {
      await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc(key)
          .set({'read': true});
    }
    await pumpPath(tester);

    expect(find.text('6 days'), findsOneWidget);
    expect(find.text('2 days'), findsOneWidget);

    await tester.tap(find.text('October 2026'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));
    expect(find.byType(StreakHistoryPage), findsOneWidget);
  });

  testWidgets('Streak history link opens streak history', (tester) async {
    await pumpPath(tester);
    await tester.tap(find.text('Streak history'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));
    expect(find.byType(StreakHistoryPage), findsOneWidget);
  });

  testWidgets(
      'Library opens Bible progress; All lists earned and unearned badges', (
    tester,
  ) async {
    await firestore
        .collection('users')
        .doc('u1')
        .collection('achievements')
        .doc('first_book')
        .set({
      'title': 'First Book',
      'dateUnlocked': Timestamp.fromDate(DateTime(2026, 9, 1)),
    });
    await pumpPath(tester);

    expect(find.text('Latest badge'), findsOneWidget);
    expect(find.text('First Book'), findsOneWidget);
    expect(find.text('Next badge'), findsOneWidget);

    await tester.ensureVisible(find.text('Library'));
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));
    expect(find.byType(BibleProgressPage), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    await tester.ensureVisible(find.text('All'));
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));
    expect(find.text('Badges'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^First Book, earned')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^First whole Bible, not yet earned')),
      findsOneWidget,
    );
  });

  testWidgets('Read-throughs shows Lap progress bars for each testament', (
    tester,
  ) async {
    // Genesis (50 chapters) is the only finished OT book this lap.
    await firestore
        .collection('users')
        .doc('u1')
        .collection('read_through_state')
        .doc('current')
        .set({
      'ot': {'Genesis': List.generate(50, (i) => i + 1)},
      'nt': <String, dynamic>{},
    });
    await pumpPath(tester);

    final ot = tester.widget<LinearProgressIndicator>(
      find.descendant(
        of: find
            .ancestor(
              of: find.text('Old\nTestament'),
              matching: find.byType(Column),
            )
            .first,
        matching: find.byType(LinearProgressIndicator),
      ),
    );
    expect(ot.value, closeTo(1 / 39, 0.0001));
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
  });
}

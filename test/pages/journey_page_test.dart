import 'dart:io';

import 'package:bible_read/pages/journey_page.dart';
import 'package:bible_read/widgets/journey/consistency_calendar.dart';
import 'package:bible_read/widgets/journey/plans_hub.dart';
import 'package:bible_read/widgets/app_header.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/models/reading_plan.dart';
import 'package:bible_read/services/reading_plan_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MockFirebaseAuth auth;
  late FakeFirebaseFirestore firestore;

  setUp(() {
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    firestore = FakeFirebaseFirestore();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    DateTime Function() dateProvider = DateTime.now,
  }) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: JourneyPage(
          auth: auth,
          firestore: firestore,
          vibrationService: const VibrationService(),
          dateProvider: dateProvider,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));
  }

  testWidgets('Path page is titled "Path"', (tester) async {
    await pumpPage(tester);

    // The header on the Journey tab renders the title "Path".
    expect(find.text('Path'), findsOneWidget);
    expect(find.byType(PlansHub), findsOneWidget);

    // And the duplicate page's files no longer exist to be routed to.
    expect(
      File('lib/pages/reading_plans_page.dart').existsSync(),
      isFalse,
    );
    expect(
      File('lib/widgets/views/reading_plans_view.dart').existsSync(),
      isFalse,
    );
  });

  test('no user-facing copy uses "group plan" as a noun', () {
    final offenders = <String>[];
    // Scan the sources for the retired copy. This file lists the banned
    // strings itself, so it is excluded from its own scan.
    final self = File('test/pages/journey_page_test.dart').path;
    for (final dir in ['lib', 'test']) {
      Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.endsWith(self))
          .forEach((f) {
        final text = f.readAsStringSync();
        if (text.contains("'Edit Group Plan'") ||
            text.contains("'New group plan'") ||
            text.contains("'Group plan updated'")) {
          offenders.add(f.path);
        }
      });
    }
    expect(offenders, isEmpty);
  });

  testWidgets('the tab carries the plan hub, tiles and calendar', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.byType(AppHeader), findsOneWidget);
    expect(find.byType(PlansHub), findsOneWidget);
    expect(find.byType(ConsistencyCalendar), findsOneWidget);
    expect(find.text('Shown up'), findsOneWidget);
    expect(find.text('Showing up'), findsOneWidget);
  });

  testWidgets('solo and shared plans list together on the tab', (
    tester,
  ) async {
    const plan = ReadingPlan(
      id: 'p1',
      title: 'Morning Light',
      description: '',
      durationDays: 2,
      tags: [],
      schedule: [
        ReadingPlanDay(day: 1, readings: ['Gen 1']),
        ReadingPlanDay(day: 2, readings: ['Gen 2']),
      ],
    );
    await firestore.collection('custom_plans').doc('p1').set({
      ...plan.toJson(),
      'userId': 'u1',
    });
    await ReadingPlanService(firestore: firestore)
        .startPlan('u1', 'p1', startDate: DateTime.now());
    final groupRef = firestore.collection('groups').doc('g1');
    await groupRef.set({
      'name': 'Evening Circle',
      'ownerUid': 'u2',
      'memberCount': 2,
    });
    await groupRef.collection('members').doc('u1').set({
      'uid': 'u1',
      'role': 'member',
    });
    await groupRef.collection('members').doc('u2').set({
      'uid': 'u2',
      'role': 'owner',
    });

    await pumpPage(tester);

    expect(find.text('Morning Light'), findsOneWidget);
    expect(find.text('Evening Circle'), findsOneWidget);
    expect(find.text('On your own'), findsOneWidget);
    expect(find.text('Together'), findsOneWidget);
  });

  testWidgets(
      'a reader with no plan sees an invitation and their '
      'showing-up record', (tester) async {
    await pumpPage(tester);

    expect(find.text('No active plans yet'), findsOneWidget);
    expect(find.text('Start a plan to give your reading a gentle rhythm.'),
        findsOneWidget);
    expect(find.text('Enroll in a new plan'), findsOneWidget);
    // The Showing-up record renders beside the invitation.
    expect(find.text('Shown up'), findsOneWidget);
    expect(find.text('Day streak'), findsOneWidget);
    expect(find.byType(ConsistencyCalendar), findsOneWidget);
  });

  testWidgets(
      '"Shown up · this month" counts the calendar month, including '
      'feed-only days, like the calendar', (tester) async {
    final userRef = firestore.collection('users').doc('u1');
    // Last month's days fall inside a rolling 30-day window but are not
    // "this month".
    for (final key in ['2026-08-27', '2026-08-28']) {
      await userRef.collection('reading').doc(key).set({'read': true});
    }
    for (final key in ['2026-09-10', '2026-09-11']) {
      await userRef.collection('reading').doc(key).set({'read': true});
    }
    // A day recorded only in a Group feed (no per-user reading doc), which
    // the calendar counts as shown up.
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('read_log')
        .doc('2026-09-02')
        .collection('entries')
        .doc('u1')
        .set({'uid': 'u1', 'dateId': '2026-09-02'});

    await pumpPage(tester, dateProvider: () => DateTime(2026, 9, 24, 9));

    final tile = find
        .ancestor(of: find.text('Shown up'), matching: find.byType(Column))
        .first;
    expect(
      find.descendant(of: tile, matching: find.text('3')),
      findsOneWidget,
    );
  });
}

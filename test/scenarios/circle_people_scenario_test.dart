import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:bible_read/pages/community_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/reading_status_service.dart';
import 'package:bible_read/services/nudge_service.dart';
import 'package:network_image_mock/network_image_mock.dart';
import '../helpers/firebase_seeder.dart';
import '../helpers/stub_vibration_service.dart';
import '../helpers/fake_google_sign_in_platform.dart';

/// The Circle tab, people-first (issue #802): a flat deduplicated co-member
/// list where each row shows today's Showing-up mark and what the person
/// read. Bare Showing-up marks name no scripture; Plan readings do; a
/// reader who showed up while behind shows both facts.
void main() {
  setUpAll(() {
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();
  });

  final today = DateTime(2026, 9, 8);
  final dateKey =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late GroupService groupService;
  late FirebaseSeeder seeder;

  /// Seeds a Group with [members] (uid → name); alice is the owner.
  Future<void> seedGroup(
    String groupId,
    String name,
    Map<String, String> members,
  ) async {
    await seeder.seedGroup(
      groupId: groupId,
      ownerUid: 'alice',
      name: name,
      members: members.keys.toList(),
    );
    for (final entry in members.entries) {
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(entry.key)
          .set({
        'uid': entry.key,
        'role': entry.key == 'alice' ? 'owner' : 'member',
        'name': entry.value,
      });
    }
  }

  /// Seeds [uid]'s bare Showing-up mark (the daily-habit tap) into every
  /// Group they belong to, exactly as ReadLogService.mark does.
  Future<void> seedShowingUp(String uid, Iterable<String> groupIds) async {
    for (final groupId in groupIds) {
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('read_log')
          .doc(dateKey)
          .collection('entries')
          .doc(uid)
          .set({
        'uid': uid,
        'dateId': dateKey,
        'timestamp': Timestamp.now(),
      });
    }
  }

  /// Seeds [uid]'s group-schedule progress for [dateKey] — [count] of the
  /// day's [total] scheduled chapters read. This is what a Circle row reads
  /// to say what the person read and whether they are behind.
  Future<void> seedGroupProgress(
    String groupId,
    String uid, {
    required int count,
    required int total,
    int dateOffset = 0,
  }) async {
    final d = today.add(Duration(days: dateOffset));
    final key = GroupService.dateId(d);
    await firestore
        .collection('groups')
        .doc(groupId)
        .collection('progress')
        .doc(key)
        .set({
      'total': total,
    });
    await firestore
        .collection('groups')
        .doc(groupId)
        .collection('progress')
        .doc(key)
        .collection('entries')
        .doc(uid)
        .set({'count': count, 'done': count >= total, 'dateId': key});
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'alice', displayName: 'Alice'),
      signedIn: true,
    );
    groupService = GroupService(firestore: firestore);
    seeder = FirebaseSeeder(firestore);
  });

  Future<void> pumpCircle(WidgetTester tester) async {
    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityPage(
            auth: auth,
            firestore: firestore,
            groupService: groupService,
            readingStatusService: ReadingStatusService(
              firestore: firestore,
              auth: auth,
            ),
            vibrationService: const StubVibrationService(),
            nudgeService: NudgeService(firestore: firestore),
            dateProvider: () => today,
          ),
        ),
      );
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'Circle Scenario: a flat deduplicated people list with live statuses',
    (tester) async {
      // Alice shares g1 with Bob and Cara, and g2 with Cara and Dee. Cara is
      // in both Groups — she must appear exactly once.
      await seeder.seedUser(uid: 'alice', name: 'Alice');
      await seeder.seedUser(uid: 'bob', name: 'Bob');
      await seeder.seedUser(uid: 'cara', name: 'Cara');
      await seeder.seedUser(uid: 'dee', name: 'Dee');
      await seedGroup('g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob', 'cara': 'Cara'});
      await seedGroup('g2', 'Evening', {'alice': 'Alice', 'cara': 'Cara', 'dee': 'Dee'});

      await pumpCircle(tester);

      // Every co-member appears, and the reader's own row is present.
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Cara'), findsOneWidget);
      expect(find.text('Dee'), findsOneWidget);

      // Deduplicated: exactly one Cara row despite two shared Groups.
      expect(find.text('Cara'), findsOneWidget);

      // Groups are filter chips above and a section beneath — never a
      // reading hero.
      expect(find.text('Everyone'), findsOneWidget);
      expect(find.text('Morning'), findsWidgets);
      expect(find.text('Evening'), findsWidgets);
      expect(find.text("THE COMMUNITY'S READING"), findsNothing);
    });

  testWidgets(
    'Circle Scenario: a bare Showing-up row names no scripture, '
    'a Plan-reading row does, and a behind reader shows both facts',
    (tester) async {
      await seeder.seedUser(uid: 'alice', name: 'Alice');
      await seeder.seedUser(uid: 'bob', name: 'Bob');
      await seeder.seedUser(uid: 'cara', name: 'Cara');
      await seeder.seedUser(uid: 'dee', name: 'Dee');
      await seedGroup('g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob', 'cara': 'Cara', 'dee': 'Dee'});

      // Two scheduled readings: yesterday's (Genesis 2) and today's
      // (Genesis 1). Dee skipped yesterday's — that is what being behind
      // means — while today's is still the current reading.
      final yesterday = today.subtract(const Duration(days: 1));
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('schedule')
          .doc(GroupService.dateId(yesterday))
          .set({
        'date': Timestamp.fromDate(yesterday),
        'chapters': ['Genesis 2'],
      });
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('schedule')
          .doc(dateKey)
          .set({
        'date': Timestamp.fromDate(today),
        'chapters': ['Genesis 1'],
      });

      // Bob tapped the bare Showing-up mark: entry present, no progress.
      await seedShowingUp('bob', ['g1']);

      // Cara finished today's scheduled reading: entry + progress marking
      // today's reading done. Yesterday's she also read (Genesis 2 done).
      await seedShowingUp('cara', ['g1']);
      await seedGroupProgress('g1', 'cara', count: 1, total: 1);
      await seedGroupProgress(
        'g1',
        'cara',
        count: 1,
        total: 1,
        dateOffset: -1,
      );

      // Dee showed up but is behind — yesterday's reading untouched. Both
      // facts must surface: showed up, and readings behind.
      await seedShowingUp('dee', ['g1']);
      await seedGroupProgress('g1', 'dee', count: 0, total: 1);
      await seedGroupProgress(
        'g1',
        'dee',
        count: 0,
        total: 1,
        dateOffset: -1,
      );

      await pumpCircle(tester);

      // Ordering surfaces the not-shown-up first, then just-read — never
      // alphabetical. Alice ("You") always leads.
      final you = tester.getTopLeft(find.text('You')).dy;
      final bobRow = tester.getTopLeft(find.text('Bob')).dy;
      final caraRow = tester.getTopLeft(find.text('Cara')).dy;
      final deeRow = tester.getTopLeft(find.text('Dee')).dy;
      expect(you, lessThan(bobRow));
      expect(bobRow, lessThan(caraRow));
      expect(bobRow, lessThan(deeRow));

      String statusOf(String name) {
        // The row is Padding > Row > [avatar, Expanded(Row > Column)].
        // Find the name's nearest Column, then read its second Text.
        final nameText = find.text(name);
        final statusTexts = tester.widgetList<Text>(
          find.descendant(
            of: find.ancestor(
              of: nameText,
              matching: find.byType(Column),
            ).first,
            matching: find.byType(Text),
          ),
        ).map((t) => t.data ?? '').toList();
        return statusTexts.last;
      }

      // Bob: bare Showing-up — 'Showed up', and NO scripture reference.
      expect(statusOf('Bob'), startsWith('Showed up'));
      expect(statusOf('Bob'), isNot(contains('Genesis')));

      // Cara: Plan reading — the row names the reference.
      expect(statusOf('Cara'), contains('Genesis'));

      // Dee: showed up while behind — both facts in one row.
      expect(statusOf('Dee'), contains('Showed up'));
      expect(statusOf('Dee'), contains('behind'));
    },
  );

  testWidgets(
    'Circle Scenario: filter chips narrow the list to one Group',
    (tester) async {
      await seeder.seedUser(uid: 'alice', name: 'Alice');
      await seeder.seedUser(uid: 'bob', name: 'Bob');
      await seeder.seedUser(uid: 'dee', name: 'Dee');
      await seedGroup('g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob'});
      await seedGroup('g2', 'Evening', {'alice': 'Alice', 'dee': 'Dee'});

      await pumpCircle(tester);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Dee'), findsOneWidget);

      // Tap the Morning chip: Dee (Evening only) disappears, Bob stays.
      await tester.tap(find.widgetWithText(FilterChip, 'Morning'));
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Dee'), findsNothing);

      // Everyone restores the whole Circle.
      await tester.tap(find.text('Everyone'));
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Dee'), findsOneWidget);
    },
  );

  testWidgets(
    'Circle Scenario: a row with no Reflection and no achievement '
    'still reads as complete',
    (tester) async {
      await seeder.seedUser(uid: 'alice', name: 'Alice');
      await seeder.seedUser(uid: 'bob', name: 'Bob');
      await seedGroup('g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob'});

      // Bob's complete data: showed up today. No Reflection exists anywhere
      // (#807 is later) and no achievement (#806 is later) — the row must
      // still render with name, status and mark.
      await seedShowingUp('bob', ['g1']);

      await pumpCircle(tester);

      final bobColumn = find.ancestor(
        of: find.text('Bob'),
        matching: find.byType(Column),
      ).first;
      expect(bobColumn, findsOneWidget);
      // Status line present, no placeholder-looking gaps.
      expect(
        find.descendant(of: bobColumn, matching: find.text('Showed up')),
        findsOneWidget,
      );
      expect(find.textContaining('null'), findsNothing);
 expect(find.textContaining('Reflection'), findsNothing);
    },
  );

  testWidgets(
    'Circle Scenario: Nudge is offered only for someone who has not shown up',
    (tester) async {
      await seeder.seedUser(uid: 'alice', name: 'Alice');
      await seeder.seedUser(uid: 'bob', name: 'Bob');
      await seeder.seedUser(uid: 'cara', name: 'Cara');
      await seedGroup('g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob', 'cara': 'Cara'});

      await seedShowingUp('cara', ['g1']);

      await pumpCircle(tester);

      bool rowHasNudge(String name) {
        // Walk up to the outermost Row of the person's row (the one that
        // also contains the avatar), then check for a Nudge chip inside.
        final rows = find.ancestor(
          of: find.text(name),
          matching: find.byType(Row),
        );
        final outermost = rows.last;
        return tester.any(
          find.descendant(of: outermost, matching: find.text('Nudge')),
        );
      }

      // Bob has not shown up — he gets a Nudge chip.
      expect(rowHasNudge('Bob'), isTrue);

      // Cara has shown up — no Nudge chip in her row.
      expect(rowHasNudge('Cara'), isFalse);

      // The reader's own row never offers a Nudge.
      expect(find.text('Nudge'), findsOneWidget);
    },
  );
}
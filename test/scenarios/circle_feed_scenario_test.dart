import 'dart:async';

import 'package:bible_read/models/read_through.dart';
import 'package:bible_read/pages/community_page.dart';
import 'package:bible_read/pages/create_plan_page.dart';
import 'package:bible_read/pages/group_members_page.dart';
import 'package:bible_read/pages/join_by_code_page.dart';
import 'package:bible_read/pages/share_code_page.dart';
import 'package:bible_read/services/feed_service.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/milestone_announcer.dart';
import 'package:bible_read/services/nudge_service.dart';
import 'package:bible_read/services/read_log_service.dart';
import 'package:bible_read/services/reading_status_service.dart';
import 'package:bible_read/widgets/skeleton.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../helpers/fake_google_sign_in_platform.dart';
import '../helpers/firebase_seeder.dart';
import '../helpers/stub_vibration_service.dart';

/// A [FeedService] whose Amen writes wait on [gate] and then fail.
class _FailingFeedService extends FeedService {
  _FailingFeedService(FirebaseFirestore firestore)
      : super(firestore: firestore);

  final gate = Completer<void>();

  @override
  Future<void> setAmen({
    required List<AmenTarget> targets,
    required String uid,
    required String name,
    required bool amen,
  }) async {
    await gate.future;
    throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
  }
}

/// Circle is the Feed (issue #983, ADR-0011): a status row of the Circle
/// over a seven-day Feed built from per-Group entries, likes, badge mirrors
/// and Milestones. Amen is the only reaction.
void main() {
  setUpAll(() {
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();
  });

  // A Tuesday.
  final today = DateTime(2026, 9, 8);
  final todayKey = ReadLogService.dateKeyFor(today);
  String keyFor(int daysAgo) => ReadLogService.dateKeyFor(
      DateTime(today.year, today.month, today.day - daysAgo));

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late FirebaseSeeder seeder;
  late List<String> notified;
  late List<String> nudged;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'alice', displayName: 'Alice'),
      signedIn: true,
    );
    seeder = FirebaseSeeder(firestore);
    notified = [];
    nudged = [];
  });

  /// Seeds a Group with [members] (uid → name); alice owns it.
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

  /// Seeds [uid]'s daily entry in each of [groupIds], as ReadLogService.mark
  /// (and ReflectionService for [reflection]) writes it.
  Future<void> seedEntry(
    String uid,
    List<String> groupIds, {
    int daysAgo = 0,
    int hour = 7,
    String? reflection,
  }) async {
    final dateKey = keyFor(daysAgo);
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
        'timestamp': Timestamp.fromDate(
            DateTime(today.year, today.month, today.day - daysAgo, hour)),
        if (reflection != null) 'sharedReflection': reflection,
      });
    }
  }

  DocumentReference<Map<String, dynamic>> likeRef(
    String groupId,
    String ownerUid,
    String likerUid, {
    String? dateKey,
  }) =>
      firestore
          .collection('groups')
          .doc(groupId)
          .collection('read_log')
          .doc(dateKey ?? todayKey)
          .collection('entries')
          .doc(ownerUid)
          .collection('likes')
          .doc(likerUid);

  /// Seeds [uid]'s [badgeId] in [groupId]'s badge log, as the server's
  /// badge awarding writes it.
  Future<void> seedBadge(
    String groupId,
    String uid,
    String badgeId,
    int daysAgo,
  ) =>
      firestore
          .collection('groups')
          .doc(groupId)
          .collection('badge_log')
          .doc('${uid}_$badgeId')
          .set({
        'uid': uid,
        'badgeId': badgeId,
        'dateUnlocked': Timestamp.fromDate(
            DateTime(today.year, today.month, today.day - daysAgo, 12)),
      });

  Future<void> pumpCircle(
    WidgetTester tester, {
    FeedService? feedService,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityPage(
            auth: auth,
            firestore: firestore,
            groupService: GroupService(firestore: firestore),
            readingStatusService: ReadingStatusService(
              firestore: firestore,
              auth: auth,
            ),
            vibrationService: const StubVibrationService(),
            nudgeService: NudgeService(
              firestore: firestore,
              sendNudgeNotificationFn: ({
                required String fromUid,
                required String toUid,
                required String fromName,
              }) async {
                nudged.add(toUid);
                return NudgeResult.sent;
              },
            ),
            feedService: feedService,
            onSendLikeNotification: ({
              required String ownerUid,
              required String likerName,
            }) async =>
                notified.add(ownerUid),
            dateProvider: () => today,
          ),
        ),
      );
      if (!settle) return;
      // SkeletonLoader holds for its 1000ms minimum.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    });
  }

  Finder feedText(String text) => find.descendant(
        of: find.byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('feed_')),
        matching: find.text(text),
      );

  testWidgets('skeletons show from the first frame under a persistent title',
      (tester) async {
    await seedGroup('g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob'});
    await pumpCircle(tester, settle: false);

    expect(find.text('Circle'), findsOneWidget);
    expect(find.byType(Skeleton), findsWidgets);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(Skeleton), findsNothing);
  });

  testWidgets(
      'status row: own avatar first, rings mark who has Shown up, and a '
      'not-yet person opens the Nudge sheet', (tester) async {
    await seedGroup(
        'g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob', 'cara': 'Cara'});
    await seedEntry('bob', ['g1'], reflection: 'Grace.');

    await pumpCircle(tester);

    final you = tester.getTopLeft(find.byKey(const ValueKey('status_alice')));
    final bob = tester.getTopLeft(find.byKey(const ValueKey('status_bob')));
    final cara = tester.getTopLeft(find.byKey(const ValueKey('status_cara')));
    expect(you.dx, lessThan(bob.dx));
    expect(you.dx, lessThan(cara.dx));
    expect(find.bySemanticsLabel('You, not yet today'), findsOneWidget);
    expect(find.bySemanticsLabel('Bob, shown up today'), findsOneWidget);
    expect(find.bySemanticsLabel('Cara, not yet today. Nudge'), findsOneWidget);

    // Someone who has Shown up is not nudgeable.
    await tester.tap(find.byKey(const ValueKey('status_bob')));
    await tester.pumpAndSettle();
    expect(find.text('Send nudge'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('status_cara')));
    await tester.pumpAndSettle();
    expect(find.text('Send nudge'), findsOneWidget);
    await tester.tap(find.text('Send nudge'));
    await tester.pumpAndSettle();
    expect(nudged, ['cara']);
  });

  testWidgets(
      'one update per person per day across two Groups, keeping the shared '
      'Reflection; unshared Reflections never appear', (tester) async {
    await seedGroup(
        'g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob', 'cara': 'Cara'});
    await seedGroup('g2', 'Evening', {'alice': 'Alice', 'bob': 'Bob'});
    // Bob's copies differ: only the Morning copy carries the Reflection.
    await seedEntry('bob', ['g2']);
    await seedEntry('bob', ['g1'], reflection: 'He restores my soul.');
    // Cara kept her Reflection private: it lives only in her own document.
    await seedEntry('cara', ['g1'], hour: 8);
    await firestore
        .collection('users')
        .doc('cara')
        .collection('reflections')
        .doc(todayKey)
        .set({'text': 'Just for me.', 'shared': false});

    await pumpCircle(tester);

    expect(feedText('Bob showed up'), findsOneWidget);
    expect(find.text('He restores my soul.'), findsOneWidget);
    expect(feedText('7:00 AM · Evening, Morning'), findsOneWidget);
    expect(feedText('Cara showed up'), findsOneWidget);
    expect(find.text('Just for me.'), findsNothing);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text("That's the week"), findsOneWidget);
  });

  testWidgets('a completed Plan reading names the scripture', (tester) async {
    await seedGroup('g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob'});
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('schedule')
        .doc(todayKey)
        .set({
      'date': Timestamp.fromDate(today),
      'chapters': ['John 3'],
    });
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('progress')
        .doc(todayKey)
        .collection('entries')
        .doc('bob')
        .set({'count': 1, 'done': true});
    await seedEntry('bob', ['g1']);

    await pumpCircle(tester);

    expect(feedText('Bob read John 3'), findsOneWidget);
  });

  testWidgets(
      'same-day Shown-up people without Reflections collapse into one update',
      (tester) async {
    await seedGroup('g1', 'Morning', {
      'alice': 'Alice',
      'bob': 'Ben',
      'eli': 'Eli',
    });
    await seedEntry('alice', ['g1'], hour: 6);
    await seedEntry('bob', ['g1'], hour: 8);
    await seedEntry('eli', ['g1'], hour: 7);

    await pumpCircle(tester);

    expect(feedText('Ben, Eli and you read today'), findsOneWidget);
    expect(feedText('Ben showed up'), findsNothing);
  });

  testWidgets('a large grouped day names two and counts the others',
      (tester) async {
    final people = {
      'alice': 'Alice',
      for (final n in ['Ana', 'Ben', 'Cy', 'Dot']) n.toLowerCase(): n,
    };
    await seedGroup('g1', 'Morning', people);
    var hour = 10;
    for (final uid in ['ana', 'ben', 'cy', 'dot']) {
      await seedEntry(uid, ['g1'], hour: hour--);
    }

    await pumpCircle(tester);

    expect(feedText('Ana, Ben and 2 others read today'), findsOneWidget);
  });

  testWidgets(
      'a Detected Read-Through is announced as a Milestone; a Backfilled one '
      'never appears', (tester) async {
    await seedGroup(
        'g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob', 'cara': 'Cara'});
    final announcer = MilestoneAnnouncer(firestore: firestore);
    await announcer.announce(
      uid: 'bob',
      now: DateTime(2026, 9, 8, 9),
      completed: [
        ReadThrough(
          id: 'r1',
          scope: ReadThroughScope.newTestament,
          completedAt: today,
          source: ReadThroughSource.detected,
          lapNumber: 1,
        ),
      ],
    );
    await announcer.announce(
      uid: 'cara',
      now: DateTime(2026, 9, 8, 9),
      completed: [
        ReadThrough(
          id: 'r2',
          scope: ReadThroughScope.oldTestament,
          completedAt: today,
          source: ReadThroughSource.backfilled,
          lapNumber: 1,
        ),
      ],
    );

    await pumpCircle(tester);

    expect(find.text('MILESTONE'), findsOneWidget);
    expect(feedText('Bob finished the New Testament'), findsOneWidget);
    expect(find.textContaining('Old Testament'), findsNothing);
    expect(find.textContaining('Cara'), findsWidgets); // status row only
    expect(feedText('Cara showed up'), findsNothing);
  });

  testWidgets('a Badge earned this week appears; an older one does not',
      (tester) async {
    await seedGroup(
        'g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob', 'cara': 'Cara'});
    await seedBadge('g1', 'bob', 'first_book', 1);
    await seedBadge('g1', 'cara', 'first_nt', 9);

    await pumpCircle(tester);

    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(feedText('Bob earned the First Book badge'), findsOneWidget);
    expect(find.textContaining('First New Testament'), findsNothing);
  });

  testWidgets('two Badges earned in one week both show', (tester) async {
    await seedGroup('g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob'});
    await seedBadge('g1', 'bob', 'first_book', 1);
    await seedBadge('g1', 'bob', 'first_nt', 3);

    await pumpCircle(tester);

    expect(feedText('Bob earned the First Book badge'), findsOneWidget);
    expect(
        feedText('Bob earned the First New Testament badge'), findsOneWidget);
  });

  testWidgets(
      'a Badge Amen is its own, apart from the Amen on that person\'s day',
      (tester) async {
    await seedGroup('g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob'});
    await seedEntry('bob', ['g1'], hour: 8);
    await seedBadge('g1', 'bob', 'first_book', 0);
    await likeRef('g1', 'bob', 'zed').set({'name': 'Zed'});
    final badgeLike =
        firestore.doc('groups/g1/badge_log/bob_first_book/likes/alice');

    await pumpCircle(tester);

    final day = find.byKey(ValueKey('amen_$todayKey/bob'));
    final badge = find.byKey(ValueKey('amen_$todayKey/bob_first_book'));
    expect(feedText('Bob showed up'), findsOneWidget);
    expect(feedText('Bob earned the First Book badge'), findsOneWidget);
    expect(find.descendant(of: day, matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: badge, matching: find.text('1')), findsNothing);

    await tester.tap(badge);
    await tester.pumpAndSettle();

    expect((await badgeLike.get()).exists, isTrue);
    expect((await likeRef('g1', 'bob', 'alice').get()).exists, isFalse);
    expect(
        find.descendant(of: badge, matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: day, matching: find.text('1')), findsOneWidget);
    expect(notified, ['bob']);
  });

  testWidgets('the Feed covers today and the seven days before it',
      (tester) async {
    await seedGroup('g1', 'Morning', {
      'alice': 'Alice',
      'bob': 'Bob',
      'cara': 'Cara',
      'dee': 'Dee',
    });
    await seedEntry('bob', ['g1']);
    await seedEntry('cara', ['g1'], daysAgo: 7);
    await seedEntry('dee', ['g1'], daysAgo: 8);

    await pumpCircle(tester);

    expect(find.text('TUESDAY, SEP 1'), findsOneWidget);
    expect(feedText('Cara showed up'), findsOneWidget);
    expect(feedText('Dee showed up'), findsNothing);
    final cara = tester.getTopLeft(feedText('Cara showed up')).dy;
    final bob = tester.getTopLeft(feedText('Bob showed up')).dy;
    final end = tester.getTopLeft(find.text("That's the week")).dy;
    expect(bob, lessThan(cara));
    expect(cara, lessThan(end));
  });

  testWidgets(
      'Amen toggles optimistically, writing and deleting the like in every '
      'Group the update came from', (tester) async {
    await seedGroup('g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob'});
    await seedGroup('g2', 'Evening', {'alice': 'Alice', 'bob': 'Bob'});
    await seedEntry('bob', ['g1', 'g2']);
    await likeRef('g1', 'bob', 'zed').set({'name': 'Zed'});

    await pumpCircle(tester);

    final pill = find.byKey(ValueKey('amen_$todayKey/bob'));
    expect(find.descendant(of: pill, matching: find.text('1')), findsOneWidget);

    await tester.tap(pill);
    await tester.pump();
    expect(find.descendant(of: pill, matching: find.text('2')), findsOneWidget);
    expect(
        find.descendant(
            of: pill, matching: find.byIcon(Icons.favorite_rounded)),
        findsOneWidget);
    await tester.pumpAndSettle();
    expect((await likeRef('g1', 'bob', 'alice').get()).exists, isTrue);
    expect((await likeRef('g2', 'bob', 'alice').get()).exists, isTrue);
    expect(notified, ['bob']);

    await tester.tap(pill);
    await tester.pump();
    expect(find.descendant(of: pill, matching: find.text('1')), findsOneWidget);
    await tester.pumpAndSettle();
    expect((await likeRef('g1', 'bob', 'alice').get()).exists, isFalse);
    expect((await likeRef('g2', 'bob', 'alice').get()).exists, isFalse);
  });

  testWidgets('another reader\'s Amen appears live', (tester) async {
    await seedGroup(
        'g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob', 'cara': 'Cara'});
    await seedEntry('bob', ['g1']);
    await seedBadge('g1', 'bob', 'first_book', 1);

    await pumpCircle(tester);

    final day = find.byKey(ValueKey('amen_$todayKey/bob'));
    final badge = find.byKey(ValueKey('amen_${keyFor(1)}/bob_first_book'));
    expect(find.descendant(of: day, matching: find.text('1')), findsNothing);
    expect(find.descendant(of: badge, matching: find.text('1')), findsNothing);

    await likeRef('g1', 'bob', 'cara').set({'name': 'Cara'});
    await firestore
        .doc('groups/g1/badge_log/bob_first_book/likes/cara')
        .set({'name': 'Cara'});
    await tester.pumpAndSettle();

    expect(find.descendant(of: day, matching: find.text('1')), findsOneWidget);
    expect(
        find.descendant(of: badge, matching: find.text('1')), findsOneWidget);

    await likeRef('g1', 'bob', 'cara').delete();
    await tester.pumpAndSettle();
    expect(find.descendant(of: day, matching: find.text('1')), findsNothing);
  });

  testWidgets('a failed Amen rolls back with a notice', (tester) async {
    await seedGroup('g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob'});
    await seedEntry('bob', ['g1']);
    final failing = _FailingFeedService(firestore);

    await pumpCircle(tester, feedService: failing);

    final pill = find.byKey(ValueKey('amen_$todayKey/bob'));
    await tester.tap(pill);
    await tester.pump();
    expect(find.descendant(of: pill, matching: find.text('1')), findsOneWidget);

    failing.gate.complete();
    await tester.pumpAndSettle();
    expect(find.descendant(of: pill, matching: find.text('1')), findsNothing);
    expect(find.text("Couldn't send your Amen. Please try again."),
        findsOneWidget);
    expect(notified, isEmpty);
  });

  testWidgets('filter chips narrow the status row and the Feed',
      (tester) async {
    await seedGroup('g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob'});
    await seedGroup('g2', 'Evening', {'alice': 'Alice', 'dee': 'Dee'});
    await seedEntry('bob', ['g1'], reflection: 'Morning light.');
    await seedEntry('dee', ['g2'], reflection: 'Evening rest.');

    await pumpCircle(tester);
    expect(find.byKey(const ValueKey('status_dee')), findsOneWidget);
    expect(find.text('Evening rest.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Morning'));
    await tester.pumpAndSettle();
    expect(find.text('MORNING'), findsOneWidget);
    expect(find.byKey(const ValueKey('status_bob')), findsOneWidget);
    expect(find.byKey(const ValueKey('status_dee')), findsNothing);
    expect(find.text('Morning light.'), findsOneWidget);
    expect(find.text('Evening rest.'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Everyone'));
    await tester.pumpAndSettle();
    expect(find.text('TOGETHER'), findsOneWidget);
    expect(find.text('Evening rest.'), findsOneWidget);
  });

  testWidgets(
      'Groups with nothing posted today read as not-yet, older days below',
      (tester) async {
    await seedGroup('g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob'});
    await seedEntry('bob', ['g1'], daysAgo: 1);

    await pumpCircle(tester);

    expect(find.byKey(const ValueKey('status_bob')), findsOneWidget);
    expect(find.text('No updates yet today'), findsOneWidget);
    expect(
      find.text('When someone in your Circle reads, it shows up here.'),
      findsOneWidget,
    );
    expect(find.text('TODAY'), findsNothing);
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(feedText('Bob showed up'), findsOneWidget);
  });

  testWidgets('no Groups shows the three-action empty state', (tester) async {
    await pumpCircle(tester);

    expect(find.text('No one here yet'), findsOneWidget);
    expect(
        find.text(
          'Your Circle is your Friends and everyone you share a group with.',
        ),
        findsOneWidget);
    expect(find.text('Have a code?'), findsOneWidget);
    expect(find.text('Find a group'), findsOneWidget);
    expect(find.text('Create a group'), findsOneWidget);
  });

  group('Invite sheet', () {
    Future<void> openInvite(WidgetTester tester) async {
      await seedGroup('g1', 'Morning', {'alice': 'Alice', 'bob': 'Bob'});
      await seedGroup('g2', 'Evening', {'alice': 'Alice'});
      await pumpCircle(tester);
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();
      expect(find.text('Bring people in'), findsOneWidget);
    }

    testWidgets('lists every way in and the reader\'s Groups', (tester) async {
      await openInvite(tester);
      for (final label in [
        'Share a code',
        'Have a code?',
        'Find a group',
        'Create a group',
        'YOUR GROUPS',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('2 members · Bible reading plan'), findsOneWidget);
      expect(find.text('1 member · Bible reading plan'), findsOneWidget);
    });

    testWidgets('Share a code asks which Group, then shares its code',
        (tester) async {
      await openInvite(tester);
      await tester.tap(find.text('Share a code'));
      await tester.pumpAndSettle();
      expect(find.text("Share which group's code?"), findsOneWidget);
      await tester.tap(find.text('Evening').last);
      await tester.pumpAndSettle();
      expect(find.byType(ShareCodePage), findsOneWidget);
      expect(tester.widget<ShareCodePage>(find.byType(ShareCodePage)).group.id,
          'g2');
    });

    testWidgets('Have a code? opens join by code', (tester) async {
      await openInvite(tester);
      await tester.tap(find.text('Have a code?'));
      await tester.pumpAndSettle();
      expect(find.byType(JoinByCodePage), findsOneWidget);
    });

    testWidgets('Find a group opens the public browse', (tester) async {
      await openInvite(tester);
      await tester.tap(find.text('Find a group'));
      await tester.pumpAndSettle();
      expect(find.text('Join an open group to read together.'), findsOneWidget);
    });

    testWidgets('Create a group opens plan creation on With a group',
        (tester) async {
      await openInvite(tester);
      await tester.tap(find.text('Create a group'));
      await tester.pumpAndSettle();
      final page = tester.widget<CreatePlanPage>(find.byType(CreatePlanPage));
      expect(page.initialAudience, PlanAudience.group);
    });

    testWidgets('a Group row opens its Group page', (tester) async {
      await openInvite(tester);
      await tester.tap(find.text('2 members · Bible reading plan'));
      await tester.pumpAndSettle();
      final page =
          tester.widget<GroupMembersPage>(find.byType(GroupMembersPage));
      expect(page.group.id, 'g1');
    });
  });
}

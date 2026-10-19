import 'package:bible_read/pages/community_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/nudge_service.dart';
import 'package:bible_read/services/reading_status_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingVibrationService extends VibrationService {
  @override
  Future<void> lightImpact() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late _RecordingVibrationService vibration;
  late GroupService groupService;
  late ReadingStatusService readingStatusService;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      mockUser: MockUser(
        uid: 'u1',
        displayName: 'Test User',
        photoURL: 'http://photo.url',
      ),
      signedIn: true,
    );
    vibration = _RecordingVibrationService();
    groupService = GroupService(firestore: firestore);
    readingStatusService = ReadingStatusService(
      firestore: firestore,
      auth: auth,
    );
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    DateTime? date,
    NudgeService? nudgeService,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CommunityPage(
          auth: auth,
          firestore: firestore,
          groupService: groupService,
          readingStatusService: readingStatusService,
          vibrationService: vibration,
          nudgeService: nudgeService,
          dateProvider: () => date ?? DateTime(2024, 1, 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // SkeletonLoader holds for its 1000ms minimum.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('renders header with eyebrow and title', (tester) async {
    await pumpPage(tester, date: DateTime(2024, 1, 1, 9)); // 9 AM
    expect(find.text('TOGETHER'), findsOneWidget);
    expect(find.text('Circle'), findsOneWidget);
  });

  testWidgets('renders empty group state when no groups', (tester) async {
    await pumpPage(tester);

    expect(find.text('No one here yet'), findsOneWidget);
    expect(
      find.text(
          'Your Circle is your Friends and everyone you share a group with.'),
      findsOneWidget,
    );
    expect(find.text('Have a code?'), findsOneWidget);
    expect(find.text('Find a group'), findsOneWidget);
    expect(find.text('Create a group'), findsOneWidget);
  });

  testWidgets('renders the status row with no groups beneath, no reading hero',
      (
    tester,
  ) async {
    await firestore.collection('groups').doc('g1').set({
      'name': 'My Group',
      'ownerUid': 'u1',
      'memberCount': 2,
    });
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u1')
        .set({
      'uid': 'u1',
      'role': 'owner',
      'name': 'Test User',
    });
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u2')
        .set({
      'uid': 'u2',
      'role': 'member',
      'name': 'Bea',
    });
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('schedule')
        .doc('2024-01-01')
        .set({
      'date': Timestamp.fromDate(DateTime(2024, 1, 1)),
      'chapters': ['Gen 1'],
    });

    await pumpPage(tester);

    // The reader's own avatar leads the status row.
    expect(find.text('You'), findsOneWidget);
    // Co-members render from Group membership.
    expect(find.text('Bea'), findsOneWidget);

    // "Your groups" section is removed; groups exist only as filter chips.
    expect(find.text('Your groups'), findsNothing);
    expect(find.text('My Group'), findsOneWidget);
    expect(find.text("THE COMMUNITY'S READING"), findsNothing);
    expect(find.text('Read with the community'), findsNothing);

    // The dead "Manage" passthrough is gone with the hero.
    expect(find.text('Manage'), findsNothing);
  });

  testWidgets('filter chips have a 48px target and centered label',
      (tester) async {
    await firestore.collection('groups').doc('g1').set({
      'name': 'My Group',
      'ownerUid': 'u1',
      'memberCount': 2,
    });
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u1')
        .set({
      'uid': 'u1',
      'role': 'owner',
      'name': 'Test User',
    });

    await pumpPage(tester);

    final everyoneChipFinder = find.widgetWithText(FilterChip, 'Everyone');
    expect(everyoneChipFinder, findsOneWidget);
    final filterChip = tester.widget<FilterChip>(everyoneChipFinder);
    expect(filterChip.materialTapTargetSize, MaterialTapTargetSize.padded);
    expect(filterChip.padding, EdgeInsets.zero);

    final chipBox = tester.renderObject<RenderBox>(everyoneChipFinder);
    final textBox = tester.renderObject<RenderBox>(find.text('Everyone'));
    final chipTop = chipBox.localToGlobal(Offset.zero).dy;
    final textTop = textBox.localToGlobal(Offset.zero).dy;
    final chipBottom = chipTop + chipBox.size.height;
    final textBottom = textTop + textBox.size.height;

    final topDiff = (textTop - chipTop).abs();
    final bottomDiff = (chipBottom - textBottom).abs();
    expect((topDiff - bottomDiff).abs(), lessThanOrEqualTo(1.0));
  });

  Future<void> seedFriend(String friendUid, {String name = 'Mei'}) async {
    await firestore
        .collection('users')
        .doc('u1')
        .collection('friendships')
        .doc(friendUid)
        .set({
      'uid': friendUid,
      'name': name,
      'since': DateTime(2026, 10, 3),
    });
  }

  Future<void> seedFriendDay(String friendUid, DateTime day) async {
    final key =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    await firestore
        .collection('users')
        .doc(friendUid)
        .collection('friend_feed')
        .doc(key)
        .collection('entries')
        .doc(friendUid)
        .set({
      'uid': friendUid,
      'name': 'Mei',
      'dateId': key,
      'timestamp': Timestamp.fromDate(day),
    });
  }

  testWidgets('no Friends means no Friends chip', (tester) async {
    await pumpPage(tester);

    expect(find.widgetWithText(FilterChip, 'Friends'), findsNothing);
  });

  testWidgets('the Friends chip sits after Everyone and before the groups',
      (tester) async {
    await firestore.collection('groups').doc('g1').set({
      'name': 'My Group',
      'ownerUid': 'u1',
      'memberCount': 1,
    });
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u1')
        .set({'uid': 'u1', 'role': 'owner'});
    await seedFriend('f1');

    await pumpPage(tester);

    final labels = tester
        .widgetList<FilterChip>(find.byType(FilterChip))
        .map((chip) => (chip.label as Text).data)
        .toList();
    expect(labels, ['Everyone', 'Friends', 'My Group']);
  });

  testWidgets('selecting Friends narrows the status row to Friends',
      (tester) async {
    final date = DateTime(2026, 10, 18);
    await firestore.collection('groups').doc('g1').set({
      'name': 'My Group',
      'ownerUid': 'u1',
      'memberCount': 2,
    });
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u1')
        .set({'uid': 'u1', 'role': 'owner'});
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u2')
        .set({'uid': 'u2', 'role': 'member', 'name': 'Bea'});
    await seedFriend('f1');
    await seedFriendDay('f1', date);

    await pumpPage(tester, date: date);
    expect(find.byKey(const ValueKey('status_u2')), findsOneWidget);
    expect(find.byKey(const ValueKey('status_f1')), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Friends'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('status_f1')), findsOneWidget);
    expect(find.byKey(const ValueKey('status_u2')), findsNothing);
  });

  Future<void> seedGroupWith(String uid, String name) async {
    await firestore.collection('groups').doc('g1').set({
      'name': 'My Group',
      'ownerUid': 'u1',
      'memberCount': 2,
    });
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u1')
        .set({'uid': 'u1', 'role': 'owner'});
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc(uid)
        .set({'uid': uid, 'role': 'member', 'name': name});
  }

  testWidgets('a Friend who is also a co-member is labelled with both',
      (tester) async {
    final date = DateTime(2026, 10, 18, 7);
    await seedGroupWith('f1', 'Mei');
    await seedFriend('f1');
    await seedFriendDay('f1', date);
    await firestore.doc('groups/g1/read_log/2026-10-18/entries/f1').set({
      'uid': 'f1',
      'name': 'Mei',
      'dateId': '2026-10-18',
      'timestamp': Timestamp.fromDate(date),
    });

    await pumpPage(tester, date: date);

    expect(find.text('7:00 AM · My Group · Friend'), findsOneWidget);
  });

  testWidgets('the reader’s own update is never labelled Friend',
      (tester) async {
    final date = DateTime(2026, 10, 18, 7);
    await seedFriend('f1');
    await firestore.doc('users/u1/friend_feed/2026-10-18/entries/u1').set({
      'uid': 'u1',
      'name': 'Test User',
      'dateId': '2026-10-18',
      'timestamp': Timestamp.fromDate(date),
    });

    await pumpPage(tester, date: date);

    expect(find.text('7:00 AM'), findsOneWidget);
    expect(find.text('7:00 AM · Friend'), findsNothing);
  });

  group('a Friend in the status row', () {
    late List<String> nudged;
    late NudgeService nudgeService;

    setUp(() {
      nudged = [];
      nudgeService = NudgeService(
        firestore: firestore,
        sendNudgeNotificationFn: ({
          required String fromUid,
          required String toUid,
          required String fromName,
        }) async {
          nudged.add(toUid);
          return NudgeResult.sent;
        },
      );
    });

    testWidgets('who has not Shown up is Nudged with one tap', (tester) async {
      final date = DateTime(2026, 10, 18);
      await seedFriend('f1');

      await pumpPage(tester, date: date, nudgeService: nudgeService);

      expect(
          find.bySemanticsLabel('Mei, not yet today. Nudge'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('status_f1')));
      await tester.pumpAndSettle();

      expect(find.text('Unfriend'), findsNothing);
      await tester.tap(find.text('Send nudge'));
      await tester.pumpAndSettle();
      expect(nudged, ['f1']);
    });

    testWidgets('who has Shown up does nothing on tap', (tester) async {
      final date = DateTime(2026, 10, 18, 7);
      await seedFriend('f1');
      await seedFriendDay('f1', date);

      await pumpPage(tester, date: date, nudgeService: nudgeService);

      expect(find.bySemanticsLabel('Mei, shown up today'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('status_f1')));
      await tester.pumpAndSettle();

      expect(find.text('Send nudge'), findsNothing);
      expect(find.text('Unfriend'), findsNothing);
    });

    testWidgets('still opens their sheet from the Feed', (tester) async {
      final date = DateTime(2026, 10, 18, 7);
      await seedFriend('f1');
      await seedFriendDay('f1', date);

      await pumpPage(tester, date: date, nudgeService: nudgeService);

      await tester.tap(find.text('Mei showed up'));
      await tester.pumpAndSettle();

      expect(find.text('Unfriend'), findsOneWidget);
    });
  });
}

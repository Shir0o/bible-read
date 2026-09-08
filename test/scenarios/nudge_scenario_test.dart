import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:bible_read/pages/group_members_page.dart';
import 'package:bible_read/models/group.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:network_image_mock/network_image_mock.dart';
import '../helpers/firebase_seeder.dart';
import '../helpers/stub_vibration_service.dart';
import '../helpers/fake_google_sign_in_platform.dart';

void main() {
  setUpAll(() {
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();
  });

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late GroupService groupService;
  late FriendService friendService;
  late FirebaseSeeder seeder;
  late StubVibrationService vibration;
  final sentTo = <String>[];

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'alice', displayName: 'Alice'),
      signedIn: true,
    );
    groupService = GroupService(firestore: firestore);
    friendService = FriendService(
      firestore: firestore,
      notificationService: NotificationService(firestore: firestore),
      sendNudgeNotificationFn: ({
        required String fromUid,
        required String toUid,
        required String fromName,
      }) async {
        // Mirror sendNudgeNotification: it owns both the once-per-day
        // check and the per-recipient ledger write under the sender's own
        // nudges subcollection.
        final logRef = firestore
            .collection('users')
            .doc(fromUid)
            .collection('nudges')
            .doc(toUid);
        final logDoc = await logRef.get();
        final now = DateTime(2026, 9, 8);
        if (logDoc.exists) {
          final ts = logDoc.data()?['timestamp'];
          if (ts != null) {
            final last = (ts as Timestamp).toDate();
            if (last.year == now.year &&
                last.month == now.month &&
                last.day == now.day) {
              return NudgeResult.alreadySent;
            }
          }
        }
        sentTo.add(toUid);
        await logRef.set({'timestamp': Timestamp.fromDate(now)});
        return NudgeResult.sent;
      },
    );
    seeder = FirebaseSeeder(firestore);
    vibration = const StubVibrationService();
    sentTo.clear();
  });

  Future<void> pumpMembersPage(WidgetTester tester) async {
    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: GroupMembersPage(
            group: const Group(id: 'g1', name: 'Genesis', ownerUid: 'alice'),
            groupService: groupService,
            friendService: friendService,
            auth: auth,
            vibrationService: vibration,
            currentDate: DateTime(2026, 9, 8),
          ),
        ),
      );
    });
    await tester.pumpAndSettle();
  }

  Future<void> sendNudge(WidgetTester tester) async {
    await tester.tap(find.text('Nudge'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send nudge'));
    await tester.pumpAndSettle();
  }

  Future<void> seedMemberName(String groupId, String uid, String name) async {
    await firestore
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc(uid)
        .set({
      'uid': uid,
      'role': 'member',
      'name': name,
    });
  }

  testWidgets(
    'Nudge Scenario: a co-member with no friendship can be nudged, '
    'and only once per day', (tester) async {
      // Alice and Bob share Group g1; no friendship documents exist.
      await seeder.seedUser(uid: 'alice', name: 'Alice');
      await seeder.seedUser(uid: 'bob', name: 'Bob');
      await seeder.seedGroup(
        groupId: 'g1',
        ownerUid: 'alice',
        members: ['bob'],
      );

      await seedMemberName('g1', 'bob', 'Bob');

      await pumpMembersPage(tester);

      // Bob has not read today, so his row carries the Nudge chip — no
      // friendship gate anywhere on the path.
      expect(find.text('Bob'), findsOneWidget);
      await sendNudge(tester);

      expect(find.text('Nudge sent to Bob'), findsOneWidget);
      expect(sentTo, ['bob']);

      // The callable was asked exactly once for Bob; the once-per-day
      // ledger is written under Alice's own nudges subcollection.
      final ledger = await firestore
          .collection('users')
          .doc('alice')
          .collection('nudges')
          .get();
      expect(ledger.docs.map((d) => d.id), ['bob']);
    });

  testWidgets(
    'Nudge Scenario: a second nudge the same day is refused with '
    'gentle copy', (tester) async {
      await seeder.seedUser(uid: 'alice', name: 'Alice');
      await seeder.seedUser(uid: 'bob', name: 'Bob');
      await seeder.seedGroup(
        groupId: 'g1',
        ownerUid: 'alice',
        members: ['bob'],
      );
      await seedMemberName('g1', 'bob', 'Bob');

      // Alice already nudged Bob earlier today.
      final now = DateTime(2026, 9, 8);
      await firestore
          .collection('users')
          .doc('alice')
          .collection('nudges')
          .doc('bob')
          .set({
        'timestamp': Timestamp.fromDate(now.add(const Duration(hours: 1))),
      });

      await pumpMembersPage(tester);

      final callsBeforeSheet = List<String>.from(sentTo);
      await tester.tap(find.text('Nudge'));
      await tester.pumpAndSettle();

      // Sending reports already-sent without calling the callable again.
      await tester.tap(find.text('Send nudge'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already nudged Bob'), findsOneWidget);
      expect(find.text('Nudge sent to Bob'), findsNothing);
      expect(sentTo, callsBeforeSheet);
      expect(sentTo, isEmpty);
    });

  testWidgets(
    'Nudge Scenario: a co-member shared through two Groups is nudged '
    'once, not once per Group', (tester) async {
      // Bob is in both of Alice's Groups; a Nudge is person-to-person, so
      // the recipient ledger has a single entry regardless of Group count.
      await seeder.seedUser(uid: 'alice', name: 'Alice');
      await seeder.seedUser(uid: 'bob', name: 'Bob');
      await seeder.seedGroup(
        groupId: 'g1',
        ownerUid: 'alice',
        members: ['bob'],
      );
      await seeder.seedGroup(
        groupId: 'g2',
        ownerUid: 'alice',
        name: 'Psalms',
        members: ['bob'],
      );

      await seedMemberName('g1', 'bob', 'Bob');
      await seedMemberName('g2', 'bob', 'Bob');

      await pumpMembersPage(tester);
      await sendNudge(tester);

      expect(find.text('Nudge sent to Bob'), findsOneWidget);
      expect(sentTo, ['bob']);

      final ledger = await firestore
          .collection('users')
          .doc('alice')
          .collection('nudges')
          .get();
      // One recipient document — keyed by recipient, no group dimension.
      expect(ledger.docs.map((d) => d.id), ['bob']);
    });
}
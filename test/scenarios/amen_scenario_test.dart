import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/reading_status_service.dart';
import 'package:bible_read/widgets/views/read_log_view.dart';
import '../helpers/firebase_seeder.dart';
import '../helpers/stub_vibration_service.dart';

/// Amen scenario (issue #803): a reader Amens a co-member's entry in one
/// tap. The Amen registers in the per-Group feed the entry lives in, shows
/// on the card (who has Amen'd), can be undone, and notifies the author.
void main() {
  final today = DateTime(2026, 9, 8);
  final dateKey = GroupService.dateId(today);

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late FirebaseSeeder seeder;

  /// Sends the notification the app would delegate to the callable —
  /// mirrored as a direct Firestore write so the test observes the
  /// author's notification the way sendLikeNotification delivers it.
  Future<void> sendLikeNotification({
    required String ownerUid,
    required String likerName,
  }) async {
    await firestore
        .collection('users')
        .doc(ownerUid)
        .collection('notifications')
        .add({
      'type': 'amen',
      'fromUid': auth.currentUser!.uid,
      'message': '$likerName said Amen',
      'timestamp': Timestamp.now(),
      'read': false,
    });
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'alice', displayName: 'Alice'),
      signedIn: true,
    );
    seeder = FirebaseSeeder(firestore);
  });

  Future<void> pumpFeed(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadLogView(
            firestore: firestore,
            auth: auth,
            readingStatusService: ReadingStatusService(
              firestore: firestore,
              auth: auth,
            ),
            onSendLikeNotification: sendLikeNotification,
            dateProvider: () => today,
            vibrationService: const StubVibrationService(),
          ),
        ),
      ),
    );
    // The SkeletonLoader enforces a 1000ms minimum — ride it out.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Amen Scenario: a reader Amens a co-member entry in one tap, the '
      'author is notified, the Amen shows, and it can be undone',
      (tester) async {
    await seeder.seedUser(uid: 'alice', name: 'Alice');
    await seeder.seedUser(uid: 'bob', name: 'Bob');
    await seeder.seedGroup(
      groupId: 'g1',
      ownerUid: 'bob',
      name: 'Morning',
      members: ['bob', 'alice'],
    );

    // The seeder's member docs carry no `uid` field; the membership
    // queries key on it — write it directly.
    const roles = <String, String>{'bob': 'owner', 'alice': 'member'};
    for (final MapEntry(key: uid, value: role) in roles.entries) {
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('members')
          .doc(uid)
          .set({'uid': uid, 'role': role});
    }

    // Bob showed up today: his entry lives in the per-Group feed.
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('read_log')
        .doc(dateKey)
        .collection('entries')
        .doc('bob')
        .set({
      'uid': 'bob',
      'name': 'Bob',
      'dateId': dateKey,
      'timestamp': Timestamp.now(),
    });

    await pumpFeed(tester);

    // The entry renders with the Amen affordance, not yet Amen'd.
    expect(find.text('Bob'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

    // One tap Amens: optimistic UI shows the Amen immediately.
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pump();
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);

    // The Amen registers on the entry in the Group feed storage.
    final amenDoc = await firestore
        .collection('groups')
        .doc('g1')
        .collection('read_log')
        .doc(dateKey)
        .collection('entries')
        .doc('bob')
        .collection('likes')
        .doc('alice')
        .get();
    expect(amenDoc.exists, isTrue);

    // The author is notified.
    final notifications = await firestore
        .collection('users')
        .doc('bob')
        .collection('notifications')
        .get();
    expect(notifications.docs.length, 1);

    // Undo: a second tap removes the Amen — optimistic toggle.
    await tester.tap(find.byIcon(Icons.favorite_rounded));
    await tester.pump();
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.text('Alice'), findsNothing);

    final amenAfterUndo = await firestore
        .collection('groups')
        .doc('g1')
        .collection('read_log')
        .doc(dateKey)
        .collection('entries')
        .doc('bob')
        .collection('likes')
        .doc('alice')
        .get();
    expect(amenAfterUndo.exists, isFalse);
  });
}

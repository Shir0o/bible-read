// Covers the per-member self-healing side of Phase 5a.
//
// The owner rewrites the schedule on save (Phase 4). Until the cross-member
// Cloud Function lands (Phase 5b), the only progress a member can repair is
// their own — they own the rule `progress/{dateId}/entries/{uid}` writes —
// and the repair must run in-place on their next open. The owner's batch
// also bumps `planConfig.revision`; we compare that against `members/{uid}.
// remappedRevision` to know whether this group still needs a remap.
//
// Pure remap is tested in `progress_remap_test.dart`. This file exercises
// the Firestore-shaped boundary around that function.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group_plan_config.dart';
import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/models/schedule_mode.dart';
import 'package:bible_read/services/group_service.dart';

GroupPlanDraft _draft({
  required List<String> books,
  required String startRef,
  int revision = 2,
}) {
  return GroupPlanDraft(
    books: books,
    startRef: startRef,
    mode: ScheduleMode.chaptersPerDay,
    chaptersPerDay: 2,
    startDate: DateTime(2026, 9, 1),
    endDate: null,
    weekdays: const [1, 2, 3, 4, 5, 6, 7],
    bookBoundary: true,
    dayOverrides: const {},
    revision: revision,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  late FakeFirebaseFirestore firestore;
  late GroupService service;
  const groupId = 'g1';
  const uid = 'u1';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = GroupService(firestore: firestore);
  });

  group('applyOwnRemap', () {
    test(
        'moves a tick from old position to the new day that means the same '
        'chapter, and nowhere else', () async {
      // Old schedule + tick at day1 index 1 ("Jeremiah 2").
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.schedule)
          .doc('2026-09-01')
          .set({
        'date': Timestamp.fromDate(DateTime(2026, 9, 1)),
        'chapters': ['Jeremiah 1', 'Jeremiah 2'],
      });
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.schedule)
          .doc('2026-09-02')
          .set({
        'date': Timestamp.fromDate(DateTime(2026, 9, 2)),
        'chapters': ['Jeremiah 3', 'Jeremiah 4'],
      });
      // FakeFirestore needs an explicit parent doc for the collection listing
      // to surface these day ids.
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('progress')
          .doc('2026-09-01')
          .set({'dateId': '2026-09-01'});
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('progress')
          .doc('2026-09-02')
          .set({'dateId': '2026-09-02'});
      // Member ticked day1 index 1 (Jeremiah 2) and day2 index 0 (Jeremiah 3).
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('progress')
          .doc('2026-09-01')
          .collection('entries')
          .doc(uid)
          .set({
        'uid': uid,
        'dateId': '2026-09-01',
        'groupId': groupId,
        'count': 1,
      });
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('progress')
          .doc('2026-09-01')
          .collection('entries')
          .doc(uid)
          .collection('items')
          .doc('1')
          .set({'done': true});
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('progress')
          .doc('2026-09-02')
          .collection('entries')
          .doc(uid)
          .set({
        'uid': uid,
        'dateId': '2026-09-02',
        'groupId': groupId,
        'count': 1,
      });
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('progress')
          .doc('2026-09-02')
          .collection('entries')
          .doc(uid)
          .collection('items')
          .doc('0')
          .set({'done': true});

      // New schedule pushes every chapter into its own day.
      final newDays = [
        GroupSchedule(
          date: DateTime(2026, 9, 1),
          chapters: ['Jeremiah 1'],
        ),
        GroupSchedule(
          date: DateTime(2026, 9, 2),
          chapters: ['Jeremiah 2'],
        ),
        GroupSchedule(
          date: DateTime(2026, 9, 3),
          chapters: ['Jeremiah 3'],
        ),
        GroupSchedule(
          date: DateTime(2026, 9, 4),
          chapters: ['Jeremiah 4'],
        ),
      ];

      await service.applyOwnRemap(
        groupId: groupId,
        uid: uid,
        oldDays: [
          GroupSchedule(
            date: DateTime(2026, 9, 1),
            chapters: ['Jeremiah 1', 'Jeremiah 2'],
          ),
          GroupSchedule(
            date: DateTime(2026, 9, 2),
            chapters: ['Jeremiah 3', 'Jeremiah 4'],
          ),
        ],
        newDays: newDays,
      );

      // Jeremiah 2 lands on the new day 2.
      final moved1 = await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('progress')
          .doc('2026-09-02')
          .collection('entries')
          .doc(uid)
          .collection('items')
          .doc('0')
          .get();
      expect(moved1.exists, isTrue);

      // Jeremiah 3 lands on the new day 3.
      final moved2 = await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('progress')
          .doc('2026-09-03')
          .collection('entries')
          .doc(uid)
          .collection('items')
          .doc('0')
          .get();
      expect(moved2.exists, isTrue);

      // No leftover tick on the old day 1 (Jeremiah 2 no longer sits there).
      final oldDay1 = await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('progress')
          .doc('2026-09-01')
          .collection('entries')
          .doc(uid)
          .collection('items')
          .doc('1')
          .get();
      expect(oldDay1.exists, isFalse);
    });

    test(
        'a tick on a chapter that no longer exists is deleted and the summary '
        'cache is repaired absolutely', () async {
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.schedule)
          .doc('2026-09-01')
          .set({
        'date': Timestamp.fromDate(DateTime(2026, 9, 1)),
        'chapters': ['Isaiah 1'],
      });
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('progress')
          .doc('2026-09-01')
          .set({'dateId': '2026-09-01'});
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('progress')
          .doc('2026-09-01')
          .collection('entries')
          .doc(uid)
          .set({
        'uid': uid,
        'dateId': '2026-09-01',
        'groupId': groupId,
        'count': 1,
      });
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('progress')
          .doc('2026-09-01')
          .collection('entries')
          .doc(uid)
          .collection('items')
          .doc('0')
          .set({'done': true});
      // Stale cache — claims 5 chapters read.
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('progressSummary')
          .doc('data')
          .collection('entries')
          .doc(uid)
          .set({'uid': uid, 'completed': 5});

      // New plan has no Isaiah.
      await service.applyOwnRemap(
        groupId: groupId,
        uid: uid,
        oldDays: [
          GroupSchedule(
            date: DateTime(2026, 9, 1),
            chapters: ['Isaiah 1'],
          ),
        ],
        newDays: [
          GroupSchedule(
            date: DateTime(2026, 9, 1),
            chapters: ['Jeremiah 1'],
          ),
        ],
      );

      final entry = await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('progress')
          .doc('2026-09-01')
          .collection('entries')
          .doc(uid)
          .get();
      // The entry was emptied by the remap and is deleted outright.
      expect(entry.exists, isFalse);

      final summary = await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('progressSummary')
          .doc('data')
          .collection('entries')
          .doc(uid)
          .get();
      // The cache is now 0, not 5 — the cache was wrong and the remap repairs it.
      expect((summary.data()!['completed'] as num).toInt(), 0);
    });
  });

  group('markMemberRemapped', () {
    test('stamps members/{uid}.remappedRevision with the current revision',
        () async {
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.members)
          .doc(uid)
          .set({'uid': uid, 'role': 'owner'});

      await service.markMemberRemapped(
        groupId: groupId,
        uid: uid,
        revision: 7,
      );

      final memberSnap = await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.members)
          .doc(uid)
          .get();
      expect(memberSnap.data()!['remappedRevision'], 7);
    });
  });

  group('needsRemap', () {
    test('is true when members remappedRevision is behind planConfig revision',
        () async {
      await firestore.collection(GroupCollections.groups).doc(groupId).set({
        'name': 'g',
        'ownerUid': uid,
        'planConfig': _draft(
          books: ['Jeremiah'],
          startRef: 'Jeremiah 1',
          revision: 5,
        ).toFirestore(),
      });
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.members)
          .doc(uid)
          .set({'uid': uid, 'role': 'owner', 'remappedRevision': 3});

      final needs = await service.needsRemap(groupId: groupId, uid: uid);
      expect(needs, isTrue);
    });

    test('is false when the revisions match', () async {
      await firestore.collection(GroupCollections.groups).doc(groupId).set({
        'name': 'g',
        'ownerUid': uid,
        'planConfig': _draft(
          books: ['Jeremiah'],
          startRef: 'Jeremiah 1',
          revision: 5,
        ).toFirestore(),
      });
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.members)
          .doc(uid)
          .set({'uid': uid, 'role': 'owner', 'remappedRevision': 5});

      final needs = await service.needsRemap(groupId: groupId, uid: uid);
      expect(needs, isFalse);
    });

    test('is true when the member doc has no remappedRevision yet', () async {
      await firestore.collection(GroupCollections.groups).doc(groupId).set({
        'name': 'g',
        'ownerUid': uid,
        'planConfig': _draft(
          books: ['Jeremiah'],
          startRef: 'Jeremiah 1',
          revision: 1,
        ).toFirestore(),
      });
      await firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection(GroupCollections.members)
          .doc(uid)
          .set({'uid': uid, 'role': 'owner'});

      final needs = await service.needsRemap(groupId: groupId, uid: uid);
      expect(needs, isTrue);
    });
  });
}

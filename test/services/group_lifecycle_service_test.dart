// Group lifecycle: owner archive, 30-day trash, restore, purge, and
// per-member participation archive (#776).
//
// External behavior: archived and soft-deleted groups vanish from every
// live list; a member's participation archive hides only their own copy;
// restoring returns the group to its pre-deletion state; purge removes it.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/services/group_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GroupService lifecycle', () {
    late FakeFirebaseFirestore firestore;
    late GroupService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = GroupService(firestore: firestore);
    });

    Future<String> seedGroup(String ownerUid) async {
      final groupId = await service.createGroup(
        ownerUid: ownerUid,
        name: 'Study Together',
      );
      return groupId;
    }

    Future<String> seedMember(String groupId, String uid) async {
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(uid)
          .set({
        'uid': uid,
        'name': 'Member $uid',
        'role': 'member',
        'joinedAt': DateTime.now(),
      });
      await firestore
          .collection('groups')
          .doc(groupId)
          .update({'memberCount': 2});
      return groupId;
    }

    group('archiveGroup', () {
      test('hides the group from the live lists but keeps it restorable',
          () async {
        final groupId = await seedGroup('owner1');

        // Sanity: live before.
        expect(await service.groupsForUser('owner1').first, hasLength(1));

        await service.archiveGroup(groupId: groupId, ownerUid: 'owner1');

        // Live list no longer shows it.
        expect(await service.groupsForUser('owner1').first, isEmpty);

        // The archive listing does.
        final archived = await service.archivedGroupsForUser('owner1');
        expect(archived, hasLength(1));
        expect(archived.single.isArchived, isTrue);
        expect(archived.single.deletedAt, isNull);

        // Nothing was destroyed.
        final doc = await firestore.collection('groups').doc(groupId).get();
        expect(doc.exists, isTrue);
      });

      test('a member cannot archive a group they do not own', () async {
        final groupId = await seedGroup('owner1');
        await seedMember(groupId, 'member1');

        await expectLater(
          service.archiveGroup(groupId: groupId, ownerUid: 'member1'),
          throwsStateError,
        );
      });
    });

    group('archiveMemberParticipation', () {
      test('hides the group for this member only', () async {
        final groupId = await seedGroup('owner1');
        await seedMember(groupId, 'member1');

        await service.archiveMemberParticipation(
          groupId: groupId,
          uid: 'member1',
        );

        // The member's live list is empty; the owner still sees the group.
        expect(await service.groupsForUser('member1').first, isEmpty);
        expect(await service.groupsForUser('owner1').first, hasLength(1));

        // The member's archive listing has it.
        final archived = await service.archivedGroupsForUser('member1');
        expect(archived, hasLength(1));

        // Unarchiving brings it back.
        await service.unarchiveMemberParticipation(
          groupId: groupId,
          uid: 'member1',
        );
        expect(await service.groupsForUser('member1').first, hasLength(1));
        expect(await service.archivedGroupsForUser('member1'), isEmpty);
      });
    });

    group('softDeleteGroup and restore', () {
      test('moves the group to the trash with a 30-day deadline', () async {
        final groupId = await seedGroup('owner1');
        await seedMember(groupId, 'member1');

        final now = DateTime(2026, 9, 8, 12);
        await service.softDeleteGroup(
          groupId: groupId,
          ownerUid: 'owner1',
          now: now,
        );

        // No live list leaks it: not the owner's, not the member's, and not
        // the browse-all view.
        expect(await service.groupsForUser('owner1').first, isEmpty);
        expect(await service.groupsForUser('member1').first, isEmpty);
        expect(await service.allGroups().first, isEmpty);

        // The trash does.
        final trashed = await service.getDeletedGroups('owner1').first;
        expect(trashed, hasLength(1));
        expect(trashed.single.deleteAfter, now.add(const Duration(days: 30)));
        expect(trashed.single.preDeleteState, 'active');
      });

      test('restoring returns the group to its pre-deletion state', () async {
        final groupId = await seedGroup('owner1');
        await service.archiveGroup(groupId: groupId, ownerUid: 'owner1');
        await service.softDeleteGroup(groupId: groupId, ownerUid: 'owner1');

        await service.restoreGroup(groupId: groupId, ownerUid: 'owner1');

        // It was archived when deleted — it returns archived, not active.
        expect(await service.groupsForUser('owner1').first, isEmpty);
        final archived = await service.archivedGroupsForUser('owner1');
        expect(archived, hasLength(1));
        expect(await service.getDeletedGroups('owner1').first, isEmpty);
        final data =
            (await firestore.collection('groups').doc(groupId).get()).data()!;
        expect(data['deletedAt'], isNull);
        expect(data['deleteAfter'], isNull);
        expect(data['preDeleteState'], isNull);
      });

      test('a member cannot soft-delete or restore the group', () async {
        final groupId = await seedGroup('owner1');
        await seedMember(groupId, 'member1');

        await expectLater(
          service.softDeleteGroup(groupId: groupId, ownerUid: 'member1'),
          throwsStateError,
        );
        await expectLater(
          service.restoreGroup(groupId: groupId, ownerUid: 'member1'),
          throwsStateError,
        );
      });

      test('permanent purge removes the group document', () async {
        final groupId = await seedGroup('owner1');
        await service.softDeleteGroup(groupId: groupId, ownerUid: 'owner1');

        await service.permanentlyDeleteGroup(
          groupId: groupId,
          ownerUid: 'owner1',
        );

        final doc = await firestore.collection('groups').doc(groupId).get();
        expect(doc.exists, isFalse);
        expect(await service.getDeletedGroups('owner1').first, isEmpty);
      });
    });
  });
}

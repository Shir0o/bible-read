import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/join_code_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late GroupService groupService;
  late JoinCodeService joinCodeService;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    groupService = GroupService(firestore: firestore);
    joinCodeService = JoinCodeService(firestore: firestore);
  });

  Future<String> seedGroup({
    String name = 'Evening Readers',
    bool isPublic = false,
  }) {
    return groupService.createGroup(
      ownerUid: 'owner',
      name: name,
      isPublic: isPublic,
    );
  }

  group('code shape', () {
    test('generate returns six characters from the unambiguous alphabet', () {
      for (var i = 0; i < 50; i++) {
        final code = JoinCodeService.generate();
        expect(code.length, JoinCodeService.codeLength);
        for (final char in code.split('')) {
          expect(JoinCodeService.alphabet.contains(char), isTrue,
              reason: 'char $char is outside the alphabet');
        }
      }
    });

    test('generate excludes I, O, 0 and 1', () {
      const excluded = {'I', 'O', '0', '1'};
      for (var i = 0; i < 200; i++) {
        final code = JoinCodeService.generate();
        for (final char in code.split('')) {
          expect(excluded.contains(char), isFalse);
        }
      }
    });

    test('normalize uppercases and strips spaces and dashes', () {
      expect(JoinCodeService.normalize(' h k-2n 9p '), 'HK2N9P');
      expect(JoinCodeService.normalize('hk2n9p'), 'HK2N9P');
    });
  });

  group('ensureGroupCode', () {
    test('assigns a code to a group without one and writes the lookup',
        () async {
      // A group created before join codes existed has no code on its doc.
      await firestore.collection('groups').doc('legacy').set({
        'name': 'Evening Readers',
        'ownerUid': 'owner',
        'memberCount': 1,
      });
      final groupId = 'legacy';
      final code = await joinCodeService.ensureGroupCode(groupId);

      final updated = await firestore.collection('groups').doc(groupId).get();
      expect(updated.data()?['joinCode'], code);

      final lookup = await firestore.collection('joinCodes').doc(code).get();
      expect(lookup.data()?['groupId'], groupId);
    });

    test('returns the existing code unchanged on later calls', () async {
      final groupId = await seedGroup();
      final first = await joinCodeService.ensureGroupCode(groupId);
      final second = await joinCodeService.ensureGroupCode(groupId);

      expect(second, first);
      final lookups = await firestore
          .collection('joinCodes')
          .where('groupId', isEqualTo: groupId)
          .get();
      expect(lookups.docs, hasLength(1));
    });
  });

  group('resolve', () {
    test('resolves a code to the group with name and member count', () async {
      final groupId = await seedGroup(name: 'Evening Readers');
      final code = await joinCodeService.ensureGroupCode(groupId);

      final match = await joinCodeService.resolve(code, 'stranger');

      expect(match, isNotNull);
      expect(match!.group.id, groupId);
      expect(match.group.name, 'Evening Readers');
      expect(match.group.memberCount, 1);
      expect(match.code, code);
    });

    test('normalises case, spaces and dashes when resolving', () async {
      final groupId = await seedGroup();
      final code = await joinCodeService.ensureGroupCode(groupId);
      final messy =
          ' ${code.substring(0, 2).toLowerCase()}-${code.substring(2)} ';

      final match = await joinCodeService.resolve(messy, 'stranger');

      expect(match, isNotNull);
      expect(match!.group.id, groupId);
    });

    test('returns null for an unknown code', () async {
      final match = await joinCodeService.resolve('ZZZZZZ', 'stranger');
      expect(match, isNull);
    });

    test('returns null for a malformed code', () async {
      expect(await joinCodeService.resolve('ABC', 'stranger'), isNull);
      expect(await joinCodeService.resolve('ABCDEI', 'stranger'), isNull);
      expect(await joinCodeService.resolve('', 'stranger'), isNull);
    });

    test('marks whether the viewer is already a member', () async {
      final groupId = await seedGroup();
      final code = await joinCodeService.ensureGroupCode(groupId);

      final stranger = await joinCodeService.resolve(code, 'stranger');
      final member = await joinCodeService.resolve(code, 'owner');

      expect(stranger!.isMember, isFalse);
      expect(member!.isMember, isTrue);
    });
  });

  group('regenerate', () {
    test('issues a new code and stops the old one from resolving', () async {
      final groupId = await seedGroup();
      final oldCode = await joinCodeService.ensureGroupCode(groupId);

      final newCode = await joinCodeService.regenerate(groupId);

      expect(newCode, isNot(oldCode));

      final newMatch = await joinCodeService.resolve(newCode, 'stranger');
      expect(newMatch, isNotNull);
      expect(newMatch!.group.id, groupId);

      final oldMatch = await joinCodeService.resolve(oldCode, 'stranger');
      expect(oldMatch, isNull);

      final oldLookup =
          await firestore.collection('joinCodes').doc(oldCode).get();
      expect(oldLookup.exists, isFalse);

      final groupDoc = await firestore.collection('groups').doc(groupId).get();
      expect(groupDoc.data()?['joinCode'], newCode);
    });

    test('works when the group has no code yet', () async {
      final groupId = await seedGroup();

      final code = await joinCodeService.regenerate(groupId);

      final match = await joinCodeService.resolve(code, 'stranger');
      expect(match, isNotNull);
      expect(match!.group.id, groupId);
    });
  });

  group('collision retry', () {
    test('retries generation when the code document already exists', () async {
      await firestore.collection('joinCodes').doc('AAAAAA').set({
        'groupId': 'some-other-group',
      });
      final codes = ['AAAAAA', 'BBBBBB'];
      final service = JoinCodeService(
        firestore: firestore,
        generateCode: () => codes.removeAt(0),
      );
      await firestore.collection('groups').doc('legacy').set({
        'name': 'Evening Readers',
        'ownerUid': 'owner',
        'memberCount': 1,
      });
      const groupId = 'legacy';

      final code = await service.ensureGroupCode(groupId);

      expect(code, 'BBBBBB');
      final otherLookup =
          await firestore.collection('joinCodes').doc('AAAAAA').get();
      expect(otherLookup.data()?['groupId'], 'some-other-group');
    });
  });

  group('createGroup', () {
    test('assigns a join code to every new group', () async {
      final groupId = await seedGroup();

      final groupDoc = await firestore.collection('groups').doc(groupId).get();
      final code = groupDoc.data()?['joinCode'] as String?;
      expect(code, isNotNull);

      final match = await joinCodeService.resolve(code!, 'stranger');
      expect(match, isNotNull);
      expect(match!.group.id, groupId);
    });
  });
}

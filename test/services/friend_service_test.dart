import 'package:bible_read/services/friend_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FriendService friendService;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    friendService = FriendService(firestore: firestore);
  });

  Future<void> seedProfile(
    String uid, {
    String? name,
    String? photoUrl,
  }) async {
    await firestore.collection('users').doc(uid).set({
      if (name != null) 'name': name,
      if (photoUrl != null) 'photoUrl': photoUrl,
    });
  }

  group('code shape', () {
    test('generate returns eight characters from the unambiguous alphabet', () {
      for (var i = 0; i < 50; i++) {
        final code = FriendService.generate();
        expect(code.length, FriendService.codeLength);
        for (final char in code.split('')) {
          expect(FriendService.alphabet.contains(char), isTrue);
        }
      }
    });

    test('looksLikeCode accepts eight valid characters only', () {
      expect(FriendService.looksLikeCode('7QK4M2PX'), isTrue);
      expect(FriendService.looksLikeCode(' 7qk4-m2px '), isTrue);
      expect(FriendService.looksLikeCode('HK2N9P'), isFalse);
      expect(FriendService.looksLikeCode('7QK4M2P'), isFalse);
      expect(FriendService.looksLikeCode('7QK4M2PI'), isFalse);
    });
  });

  group('ensureMyCode', () {
    test('creates a code on first ask and keeps it stable', () async {
      final first = await friendService.ensureMyCode('alice');
      final second = await friendService.ensureMyCode('alice');

      expect(first, hasLength(8));
      expect(second, first);

      final lookup = await firestore.collection('friendCodes').doc(first).get();
      expect(lookup.data()?['ownerUid'], 'alice');

      final private = await firestore
          .collection('users')
          .doc('alice')
          .collection('private')
          .doc('friendCode')
          .get();
      expect(private.data()?['code'], first);

      final lookups = await firestore.collection('friendCodes').get();
      expect(lookups.docs, hasLength(1));
    });

    test('two readers never hold the same code', () async {
      final alice = await friendService.ensureMyCode('alice');
      final bob = await friendService.ensureMyCode('bob');
      expect(bob, isNot(alice));
    });
  });

  group('resetMyCode', () {
    test('issues a new code and retires the old lookup', () async {
      final oldCode = await friendService.ensureMyCode('alice');
      final newCode = await friendService.resetMyCode('alice');

      expect(newCode, isNot(oldCode));
      expect(
        (await firestore.collection('friendCodes').doc(oldCode).get()).exists,
        isFalse,
      );
      expect(
        (await firestore.collection('friendCodes').doc(newCode).get())
            .data()?['ownerUid'],
        'alice',
      );

      await seedProfile('alice', name: 'Alice');
      expect(await friendService.resolve(oldCode, 'bob'), isNull);
      expect(await friendService.resolve(newCode, 'bob'), isNotNull);
    });

    test('leaves existing friendships untouched', () async {
      await friendService.ensureMyCode('alice');
      await firestore
          .collection('users')
          .doc('alice')
          .collection('friends')
          .doc('bob')
          .set({'uid': 'bob'});

      await friendService.resetMyCode('alice');

      final friend = await firestore
          .collection('users')
          .doc('alice')
          .collection('friends')
          .doc('bob')
          .get();
      expect(friend.exists, isTrue);
    });
  });

  group('resolve', () {
    test('names the code owner for the preview', () async {
      await seedProfile('alice', name: 'Alice Chen', photoUrl: 'https://a');
      final code = await friendService.ensureMyCode('alice');

      final match =
          await friendService.resolve(' ${code.toLowerCase()} ', 'bob');

      expect(match, isNotNull);
      expect(match!.ownerUid, 'alice');
      expect(match.name, 'Alice Chen');
      expect(match.photoUrl, 'https://a');
      expect(match.isSelf, isFalse);
      expect(match.isFriend, isFalse);
    });

    test('flags the reader’s own code', () async {
      await seedProfile('alice', name: 'Alice');
      final code = await friendService.ensureMyCode('alice');
      final match = await friendService.resolve(code, 'alice');
      expect(match?.isSelf, isTrue);
    });

    test('flags an existing Friend', () async {
      await seedProfile('alice', name: 'Alice');
      final code = await friendService.ensureMyCode('alice');
      await firestore
          .collection('users')
          .doc('bob')
          .collection('friends')
          .doc('alice')
          .set({'uid': 'alice'});

      final match = await friendService.resolve(code, 'bob');
      expect(match?.isFriend, isTrue);
    });

    test('returns null for unknown and malformed codes', () async {
      expect(await friendService.resolve('ZZZZZZZZ', 'bob'), isNull);
      expect(await friendService.resolve('ABC', 'bob'), isNull);
      expect(await friendService.resolve('', 'bob'), isNull);
    });
  });

  group('watchFriends', () {
    test('streams each side with name, photo and since', () async {
      await firestore
          .collection('users')
          .doc('alice')
          .collection('friends')
          .doc('bob')
          .set({
        'uid': 'bob',
        'name': 'Bob',
        'photoUrl': 'https://b',
        'since': DateTime(2026, 10, 3),
      });

      final friends = await friendService.watchFriends('alice').first;

      expect(friends, hasLength(1));
      expect(friends.single.uid, 'bob');
      expect(friends.single.name, 'Bob');
      expect(friends.single.photoUrl, 'https://b');
      expect(friends.single.since, DateTime(2026, 10, 3));
    });

    test('fetchFriendIds returns the ids', () async {
      await firestore
          .collection('users')
          .doc('alice')
          .collection('friends')
          .doc('bob')
          .set({'uid': 'bob'});

      expect(await friendService.fetchFriendIds('alice'), {'bob'});
    });
  });

  group('redeem', () {
    test('delegates the normalised code to the callable', () async {
      String? sent;
      final service = FriendService(
        firestore: firestore,
        redeemFriendCodeFn: (code) async {
          sent = code;
          return FriendRedemption.added;
        },
      );

      final result = await service.redeem(' 7qk4-m2px ');

      expect(result, FriendRedemption.added);
      expect(sent, '7QK4M2PX');
    });
  });

  group('unfriend', () {
    test('delegates to the callable', () async {
      String? sent;
      final service = FriendService(
        firestore: firestore,
        unfriendFn: (uid) async => sent = uid,
      );

      await service.unfriend('bob');
      expect(sent, 'bob');
    });
  });

  group('deleteMyFriendData', () {
    test('delegates to the account-deletion callable', () async {
      var called = false;
      final service = FriendService(
        firestore: firestore,
        deleteFriendDataFn: () async => called = true,
      );

      await service.deleteMyFriendData();
      expect(called, isTrue);
    });
  });
}

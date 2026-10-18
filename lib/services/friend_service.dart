import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/friend.dart';
import 'join_code_service.dart';

/// A resolved friend code: whose it is, and whether the viewer may add them.
class FriendCodeMatch {
  /// The normalised code that was resolved.
  final String code;

  /// UID of the reader who owns the code.
  final String ownerUid;

  /// The owner's display name, when their profile carries one.
  final String? name;

  /// The owner's profile photo URL, when known.
  final String? photoUrl;

  /// Whether the viewer typed their own code.
  final bool isSelf;

  /// Whether the viewer is already Friends with the owner.
  final bool isFriend;

  const FriendCodeMatch({
    required this.code,
    required this.ownerUid,
    this.name,
    this.photoUrl,
    this.isSelf = false,
    this.isFriend = false,
  });
}

/// The outcome of redeeming a friend code.
enum FriendRedemption {
  /// The two readers are now Friends.
  added,

  /// The code belongs to the reader who typed it.
  self,

  /// The code is unknown, malformed or was reset.
  unknown,

  /// The two readers are already Friends.
  alreadyFriends,
}

/// Signature for calling the `redeemFriendCode` Cloud Function.
typedef RedeemFriendCodeFn = Future<FriendRedemption> Function(String code);

/// Signature for calling the `unfriend` Cloud Function.
typedef UnfriendFn = Future<void> Function(String friendUid);

/// Signature for calling the `deleteFriendData` Cloud Function.
typedef DeleteFriendDataFn = Future<void> Function();

/// Friend codes and the mutual Friend connection (ADR-0012).
///
/// Each reader has one stable eight-character code, drawn from the same
/// unambiguous alphabet as group join codes. The code is stored twice:
/// - `users/{uid}/private/friendCode` carries it on the owner's private data
///   for display (never on the publicly readable profile).
/// - `friendCodes/{code}` carries the owner's uid, so a code is unique by the
///   write itself and resolves with a point read. Listing is denied.
///
/// The lookup is a "who is this?" pointer, not an authorisation token: the
/// code owner hands it over, and redeeming it is the consent. The callable
/// writes both sides of the friendship atomically, because a client may not
/// write another reader's side.
class FriendService {
  /// Firestore collection holding code → owner lookups.
  static const String collection = 'friendCodes';

  /// The per-author Fan-out read by their Friends: daily entries and Amens.
  static const String feedCollection = 'friend_feed';

  /// The per-author log of Badges, read by their Friends.
  static const String badgeLog = 'friend_badge_log';

  /// Length of a friend code.
  static const int codeLength = 8;

  /// Unambiguous alphabet, shared with join codes: I, O, 0 and 1 excluded.
  static const String alphabet = JoinCodeService.alphabet;

  static const int _maxAttempts = 8;

  /// Firestore instance used for database operations.
  final FirebaseFirestore firestore;

  final String Function() _generateCode;
  final RedeemFriendCodeFn _redeemFn;
  final UnfriendFn _unfriendFn;
  final DeleteFriendDataFn _deleteFriendDataFn;

  FriendService({
    FirebaseFirestore? firestore,
    String Function()? generateCode,
    RedeemFriendCodeFn? redeemFriendCodeFn,
    UnfriendFn? unfriendFn,
    DeleteFriendDataFn? deleteFriendDataFn,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        _generateCode = generateCode ?? generate,
        _redeemFn = redeemFriendCodeFn ?? _defaultRedeem,
        _unfriendFn = unfriendFn ?? _defaultUnfriend,
        _deleteFriendDataFn = deleteFriendDataFn ?? _defaultDeleteFriendData;

  /// Generates a random code from [alphabet].
  static String generate() {
    final rng = Random.secure();
    return List.generate(
      codeLength,
      (_) => alphabet[rng.nextInt(alphabet.length)],
    ).join();
  }

  /// Normalises raw user input: uppercase, strip whitespace and dashes.
  static String normalize(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');

  /// Whether [raw] looks like a friend code (eight characters, valid
  /// alphabet). The "Have a code?" field uses this to route 8 vs 6.
  static bool looksLikeCode(String raw) {
    final code = normalize(raw);
    return code.length == codeLength && code.split('').every(alphabet.contains);
  }

  DocumentReference<Map<String, dynamic>> _privateCode(String uid) =>
      firestore.collection('users').doc(uid).collection('private').doc(
            'friendCode',
          );

  DocumentReference<Map<String, dynamic>> _friendDoc(
    String uid,
    String friendUid,
  ) =>
      firestore
          .collection('users')
          .doc(uid)
          .collection('friends')
          .doc(friendUid);

  Future<String> _claimNewCode(Transaction tx, String uid) async {
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final code = _generateCode();
      final ref = firestore.collection(collection).doc(code);
      if ((await tx.get(ref)).exists) continue;
      tx.set(ref, {'ownerUid': uid});
      return code;
    }
    throw StateError('Could not generate a unique friend code');
  }

  /// Returns the reader's code, creating one on first ask. Safe to call
  /// repeatedly: the first code stays until [resetMyCode].
  Future<String> ensureMyCode(String uid) async {
    final ref = _privateCode(uid);
    final existing = (await ref.get()).data()?['code'];
    if (existing is String && existing.isNotEmpty) return existing;

    return firestore.runTransaction<String>((tx) async {
      final snap = await tx.get(ref);
      final current = snap.data()?['code'];
      if (current is String && current.isNotEmpty) return current;
      final code = await _claimNewCode(tx, uid);
      tx.set(
        ref,
        {'code': code, 'updatedAt': Timestamp.now()},
        SetOptions(merge: true),
      );
      return code;
    });
  }

  /// Replaces the reader's code. The old lookup is deleted in the same
  /// transaction, so a reset code stops resolving at once. Friendships are
  /// untouched.
  Future<String> resetMyCode(String uid) async {
    final ref = _privateCode(uid);
    return firestore.runTransaction<String>((tx) async {
      final snap = await tx.get(ref);
      final oldCode = snap.data()?['code'];
      final code = await _claimNewCode(tx, uid);
      tx.set(
        ref,
        {'code': code, 'updatedAt': Timestamp.now()},
        SetOptions(merge: true),
      );
      if (oldCode is String && oldCode.isNotEmpty && oldCode != code) {
        tx.delete(firestore.collection(collection).doc(oldCode));
      }
      return code;
    });
  }

  /// Resolves raw user input to its owner for the confirm preview, or null
  /// when the code is malformed, unknown, reset, or points at a deleted
  /// reader. Self and already-Friends matches are returned with their flags
  /// so the UI can explain them.
  Future<FriendCodeMatch?> resolve(String raw, String viewerUid) async {
    final code = normalize(raw);
    if (!looksLikeCode(code)) return null;

    final lookup = await firestore.collection(collection).doc(code).get();
    final ownerUid = lookup.data()?['ownerUid'] as String?;
    if (!lookup.exists || ownerUid == null || ownerUid.isEmpty) return null;

    final profile = await firestore.collection('users').doc(ownerUid).get();
    if (!profile.exists) return null;

    final isSelf = ownerUid == viewerUid;
    final isFriend =
        !isSelf && (await _friendDoc(viewerUid, ownerUid).get()).exists;

    return FriendCodeMatch(
      code: code,
      ownerUid: ownerUid,
      name: _displayName(profile.data()),
      photoUrl: _photoUrl(profile.data()),
      isSelf: isSelf,
      isFriend: isFriend,
    );
  }

  static String? _displayName(Map<String, dynamic>? data) {
    final name = (data?['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;
    final displayName = (data?['displayName'] as String?)?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final email = (data?['email'] as String?)?.trim();
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return null;
  }

  static String? _photoUrl(Map<String, dynamic>? data) {
    final photo = (data?['photoUrl'] as String?)?.trim();
    return (photo == null || photo.isEmpty) ? null : photo;
  }

  /// Live stream of the reader's Friends, newest connection first.
  Stream<List<Friend>> watchFriends(String uid) {
    return firestore
        .collection('users')
        .doc(uid)
        .collection('friends')
        .snapshots()
        .map((snap) {
      final friends = [
        for (final doc in snap.docs)
          Friend(
            uid: (doc.data()['uid'] as String?) ?? doc.id,
            name: _displayName(doc.data()),
            photoUrl: _photoUrl(doc.data()),
            since: (doc.data()['since'] as Timestamp?)?.toDate(),
          ),
      ];
      friends.sort((a, b) {
        final at = a.since ?? DateTime(0);
        final bt = b.since ?? DateTime(0);
        return bt.compareTo(at);
      });
      return friends;
    });
  }

  /// One-shot set of the reader's Friends' uids.
  Future<Set<String>> fetchFriendIds(String uid) async {
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('friends')
        .get();
    return {
      for (final doc in snap.docs) (doc.data()['uid'] as String?) ?? doc.id,
    };
  }

  /// Redeems [raw] and makes both readers Friends. The server resolves the
  /// code again, so a reset or stale code cannot slip through between the
  /// preview and the confirmation.
  Future<FriendRedemption> redeem(String raw) => _redeemFn(normalize(raw));

  /// Ends the friendship with [friendUid] for both readers, silently.
  Future<void> unfriend(String friendUid) => _unfriendFn(friendUid);

  /// Removes everything the reader owns in the friend graph: their code
  /// lookup, both sides of every friendship, and their Friend source. Called
  /// during account deletion (ADR-0006); the server does it because a client
  /// may not delete another reader's side.
  Future<void> deleteMyFriendData() => _deleteFriendDataFn();

  static Future<FriendRedemption> _defaultRedeem(String code) async {
    final callable = FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('redeemFriendCode');
    final result = await callable.call<Map<String, dynamic>>({'code': code});
    return _redemptionFrom(result.data['status']);
  }

  static Future<void> _defaultUnfriend(String friendUid) async {
    final callable = FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('unfriend');
    await callable.call<Map<String, dynamic>>({'friendUid': friendUid});
  }

  static Future<void> _defaultDeleteFriendData() async {
    final callable = FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('deleteFriendData');
    await callable.call<Map<String, dynamic>>();
  }

  static FriendRedemption _redemptionFrom(Object? status) {
    return switch (status) {
      'self' => FriendRedemption.self,
      'alreadyFriends' => FriendRedemption.alreadyFriends,
      'added' || 'ok' => FriendRedemption.added,
      _ => FriendRedemption.unknown,
    };
  }
}

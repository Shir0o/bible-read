import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/group.dart';
import 'group_service.dart';

/// The result of resolving a join code: the group it redeems to and whether
/// the viewer already belongs to it.
class JoinCodeMatch {
  /// The normalised code that was resolved.
  final String code;

  /// The group the code redeems to.
  final Group group;

  /// Whether the viewer is already a member of the group.
  final bool isMember;

  /// Creates a [JoinCodeMatch].
  const JoinCodeMatch({
    required this.code,
    required this.group,
    required this.isMember,
  });
}

/// Generates, shares and redeems per-group join codes.
///
/// A code is six characters drawn from an alphabet that excludes I, O, 0 and
/// 1, so a spoken or handwritten code is not misread. It is stored twice: as
/// `joinCode` on the group document for display, and as the document id of a
/// `joinCodes/{code}` lookup carrying the group id, which makes uniqueness a
/// property of the write itself — two groups can never claim the same code,
/// and redemption is a point read rather than a query.
///
/// A code is a low-friction invite, not an authorisation token: it grants
/// exactly what group membership grants. Redemption honours the group's own
/// gate — public groups join directly, private groups create a join request
/// for the owner to approve.
class JoinCodeService {
  /// Firestore collection holding code → group lookups.
  static const String collection = 'joinCodes';

  /// Length of a generated code.
  static const int codeLength = 6;

  /// Unambiguous alphabet for codes: I, O, 0 and 1 excluded.
  static const String alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Attempts to find an unused code before giving up. The alphabet gives
  /// 32^6 (~1B) codes, so exhausting even a handful of attempts is
  /// implausible; the cap keeps a pathological generator from looping.
  static const int _maxAttempts = 8;

  /// Firestore instance used for database operations.
  final FirebaseFirestore firestore;

  final String Function() _generateCode;

  /// Creates a [JoinCodeService] using [FirebaseFirestore.instance] by
  /// default. [generateCode] overrides code generation for tests.
  JoinCodeService({
    FirebaseFirestore? firestore,
    String Function()? generateCode,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        _generateCode = generateCode ?? generate;

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

  static String? _currentCode(DocumentSnapshot<Map<String, dynamic>> snap) {
    final code = snap.data()?['joinCode'] as String?;
    if (code == null || code.isEmpty) return null;
    return code;
  }

  /// Reserves a fresh, unused code inside [tx] and returns it. The lookup
  /// document is staged in the same transaction, so a concurrent writer
  /// claiming the same code conflicts and retries.
  Future<String> _claimNewCode(
    Transaction tx,
    String groupId,
  ) async {
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final code = _generateCode();
      final codeRef = firestore.collection(collection).doc(code);
      if ((await tx.get(codeRef)).exists) continue;
      tx.set(codeRef, {'groupId': groupId});
      return code;
    }
    throw StateError('Could not generate a unique join code');
  }

  /// Returns the group's code, generating one if the group predates join
  /// codes. Safe to call repeatedly.
  Future<String> ensureGroupCode(String groupId) async {
    final groupRef = firestore.collection(GroupCollections.groups).doc(groupId);
    final current = _currentCode(await groupRef.get());
    if (current != null) return current;
    return firestore.runTransaction<String>((tx) async {
      final existing = _currentCode(await tx.get(groupRef));
      if (existing != null) return existing;
      final code = await _claimNewCode(tx, groupId);
      tx.update(groupRef, {'joinCode': code});
      return code;
    });
  }

  /// Replaces the group's code. The previous code stops resolving; any stale
  /// lookup for the group is retired so a regenerated group has exactly one.
  Future<String> regenerate(String groupId) async {
    final groupRef = firestore.collection(GroupCollections.groups).doc(groupId);
    return firestore.runTransaction<String>((tx) async {
      final snap = await tx.get(groupRef);
      if (!snap.exists) {
        throw StateError('Group does not exist');
      }
      final oldCode = _currentCode(snap);
      final code = await _claimNewCode(tx, groupId);
      tx.update(groupRef, {'joinCode': code});
      if (oldCode != null && oldCode != code) {
        tx.delete(firestore.collection(collection).doc(oldCode));
      }
      return code;
    });
  }

  /// Resolves raw user input to the group it redeems to, or null when the
  /// code is malformed, unknown, or its group no longer exists. Normalises
  /// the input first: case, spaces and dashes are ignored.
  Future<JoinCodeMatch?> resolve(String raw, String viewerUid) async {
    final code = normalize(raw);
    if (code.length != codeLength || !code.split('').every(alphabet.contains)) {
      return null;
    }

    final codeSnap = await firestore.collection(collection).doc(code).get();
    final groupId = codeSnap.data()?['groupId'] as String?;
    if (!codeSnap.exists || groupId == null) return null;

    final groupRef = firestore.collection(GroupCollections.groups).doc(groupId);
    final groupSnap = await groupRef.get();
    if (!groupSnap.exists) return null;

    final memberSnap = await groupRef
        .collection(GroupCollections.members)
        .doc(viewerUid)
        .get();
    return JoinCodeMatch(
      code: code,
      group: Group.fromFirestore(groupSnap),
      isMember: memberSnap.exists,
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/read_through.dart';

/// Owns the ledger of times a user has finished the Old Testament, the New
/// Testament and — by derivation — the whole Bible.
///
/// Two counters are real: the Old and New Testaments each have laps that reset
/// when they complete. The whole Bible has no lap of its own. A user has read
/// the whole Bible as many times as they have read the lesser of the two
/// testaments, so whole-Bible records are *derived*: the service creates one
/// whenever an unpaired Old Testament and an unpaired New Testament pair off,
/// oldest with oldest. Derived records are still stored, so they can carry
/// their own date and location.
///
/// See `docs/adr/0002-read-through-tracking.md`.
class ReadThroughService {
  ReadThroughService({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore firestore;

  /// Subcollection holding a user's read-throughs. Owner-only read: the public
  /// announcement of a read-through is a separate object on the day's read log.
  static const String collectionName = 'read_throughs';

  CollectionReference<Map<String, dynamic>> _collection(String uid) => firestore
      .collection('users')
      .doc(uid)
      .collection(collectionName);

  /// All of [uid]'s read-throughs, oldest first, with lap numbers assigned.
  Future<List<ReadThrough>> fetchAll(String uid) async {
    final snap = await _collection(uid).get();
    return _withLapNumbers(
      snap.docs.map(ReadThrough.fromFirestore).toList(),
    );
  }

  /// Streams [uid]'s read-throughs, oldest first, with lap numbers assigned.
  Stream<List<ReadThrough>> watch(String uid) {
    return _collection(uid).snapshots().map(
          (snap) => _withLapNumbers(
            snap.docs.map(ReadThrough.fromFirestore).toList(),
          ),
        );
  }

  /// Counts the testament laps in [rows]. The whole-Bible count follows from
  /// them; it is never tallied from the derived records themselves.
  static ReadThroughCounts countsFrom(List<ReadThrough> rows) {
    return ReadThroughCounts(
      oldTestament: _ofScope(rows, ReadThroughScope.oldTestament).length,
      newTestament: _ofScope(rows, ReadThroughScope.newTestament).length,
    );
  }

  /// Records a read-through the app detected from coverage, then settles any
  /// whole-Bible record that just became true.
  ///
  /// Returns every record created, newest concept first: the testament record,
  /// followed by a derived whole-Bible record when this one closed a pair. The
  /// caller shows one celebration covering all of them.
  Future<List<ReadThrough>> recordDetected({
    required String uid,
    required ReadThroughScope scope,
    required DateTime completedAt,
    String location = '',
  }) {
    assert(
      scope != ReadThroughScope.wholeBible,
      'The whole Bible is derived, never detected directly.',
    );
    return _addPrimary(
      uid: uid,
      scopes: [scope],
      completedAt: completedAt,
      precision: DatePrecision.day,
      location: location,
      source: ReadThroughSource.detected,
    );
  }

  /// Adds a read-through the user entered by hand.
  ///
  /// Choosing [ReadThroughScope.wholeBible] records both testaments — reading
  /// the whole Bible *is* reading both — which then derives the whole-Bible
  /// record through the usual pairing.
  Future<List<ReadThrough>> addBackfilled({
    required String uid,
    required ReadThroughScope scope,
    required DateTime completedAt,
    required DatePrecision precision,
    String location = '',
    ReadThroughSource source = ReadThroughSource.backfilled,
  }) {
    final scopes = scope == ReadThroughScope.wholeBible
        ? [ReadThroughScope.oldTestament, ReadThroughScope.newTestament]
        : [scope];
    return _addPrimary(
      uid: uid,
      scopes: scopes,
      completedAt: completedAt,
      precision: precision,
      location: location,
      source: source,
    );
  }

  /// Edits the human-supplied parts of a record. The app's own account of what
  /// happened — the scope and the fact of it — is never editable.
  Future<void> updateDetails(
    String uid,
    String id, {
    DateTime? completedAt,
    DatePrecision? datePrecision,
    String? location,
  }) async {
    await _collection(uid).doc(id).update({
      if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt),
      if (datePrecision != null) 'datePrecision': datePrecision.id,
      if (location != null) 'location': location,
    });
  }

  /// Deletes a hand-entered record, then removes any whole-Bible record that
  /// no longer has a pair behind it.
  ///
  /// Detected and derived records are the app's own account of what happened
  /// and cannot be deleted; this throws [StateError] for them.
  Future<void> delete(String uid, String id) async {
    final doc = await _collection(uid).doc(id).get();
    if (!doc.exists) return;
    final row = ReadThrough.fromFirestore(doc);
    if (!row.source.isDeletable) {
      throw StateError(
        'A ${row.source.id} read-through cannot be deleted.',
      );
    }
    await _collection(uid).doc(id).delete();
    await _reconcileDerived(uid);
  }

  /// Records the app has not yet celebrated, oldest first.
  Future<List<ReadThrough>> uncelebrated(String uid) async {
    final rows = await fetchAll(uid);
    return rows
        .where((r) => !r.celebrated && r.source != ReadThroughSource.backfilled)
        .where((r) => r.source != ReadThroughSource.migrated)
        .toList();
  }

  /// Marks records as celebrated so the moment is never replayed.
  Future<void> markCelebrated(String uid, Iterable<String> ids) async {
    final batch = firestore.batch();
    for (final id in ids) {
      batch.update(_collection(uid).doc(id), {'celebrated': true});
    }
    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<List<ReadThrough>> _addPrimary({
    required String uid,
    required List<ReadThroughScope> scopes,
    required DateTime completedAt,
    required DatePrecision precision,
    required String location,
    required ReadThroughSource source,
  }) async {
    final created = <ReadThrough>[];
    for (final scope in scopes) {
      final data = ReadThrough(
        id: '',
        scope: scope,
        completedAt: completedAt,
        datePrecision: precision,
        location: location,
        source: source,
        // A record the user entered about the past is not a moment to
        // celebrate, so it is born already celebrated.
        celebrated: source != ReadThroughSource.detected,
      ).toFirestore();
      final ref = await _collection(uid).add(data);
      created.add(ReadThrough.fromFirestore(await ref.get()));
    }
    created.addAll(await _reconcileDerived(uid));

    // Lap numbers only mean anything against the whole ledger, so read the
    // new records back out of it rather than numbering them among themselves.
    final createdIds = created.map((r) => r.id).toSet();
    final ledger = await fetchAll(uid);

    return ledger.where((r) => createdIds.contains(r.id)).toList();
  }

  /// Makes the stored whole-Bible records match `min(otLaps, ntLaps)`.
  ///
  /// Pairs oldest with oldest, so a user who read three New Testaments and two
  /// Old Testaments has two whole Bibles and a New Testament still waiting for
  /// its pair. Returns the records this call created.
  Future<List<ReadThrough>> _reconcileDerived(String uid) async {
    final rows = await fetchAll(uid);
    final ot = _ofScope(rows, ReadThroughScope.oldTestament);
    final nt = _ofScope(rows, ReadThroughScope.newTestament);
    final derived = _ofScope(rows, ReadThroughScope.wholeBible);

    final pairs = ot.length < nt.length ? ot.length : nt.length;

    // Too many: a hand-entered testament record was deleted out from under a
    // whole-Bible record. Drop the newest ones back to the true count.
    if (derived.length > pairs) {
      final batch = firestore.batch();
      for (final stale in derived.sublist(pairs)) {
        batch.delete(_collection(uid).doc(stale.id));
      }
      await batch.commit();
      return const [];
    }

    final created = <ReadThrough>[];
    for (var i = derived.length; i < pairs; i++) {
      // The pair closes when its later half lands, and it happened wherever
      // that half happened.
      final closedBy =
          ot[i].completedAt.isAfter(nt[i].completedAt) ? ot[i] : nt[i];
      final data = ReadThrough(
        id: '',
        scope: ReadThroughScope.wholeBible,
        completedAt: closedBy.completedAt,
        datePrecision: closedBy.datePrecision,
        location: closedBy.location,
        source: ReadThroughSource.derived,
        celebrated: closedBy.source != ReadThroughSource.detected,
        pairedOtId: ot[i].id,
        pairedNtId: nt[i].id,
      ).toFirestore();
      final ref = await _collection(uid).add(data);
      created.add(ReadThrough.fromFirestore(await ref.get()));
    }
    return created;
  }

  static List<ReadThrough> _ofScope(
    List<ReadThrough> rows,
    ReadThroughScope scope,
  ) {
    final matching = rows.where((r) => r.scope == scope).toList()
      ..sort((a, b) => a.completedAt.compareTo(b.completedAt));
    return matching;
  }

  /// Numbers each record within its own scope, oldest first.
  static List<ReadThrough> _withLapNumbers(List<ReadThrough> rows) {
    final counters = <ReadThroughScope, int>{};
    final ordered = [...rows]
      ..sort((a, b) => a.completedAt.compareTo(b.completedAt));
    final numbered = <String, int>{};
    for (final row in ordered) {
      final next = (counters[row.scope] ?? 0) + 1;
      counters[row.scope] = next;
      numbered[row.id] = next;
    }
    return ordered
        .map((r) => r.copyWith(lapNumber: numbered[r.id] ?? 0))
        .toList();
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/lap_coverage.dart';
import '../models/read_through.dart';
import 'read_through_service.dart';
import 'reference_parser.dart';

/// What a marking turned out to complete.
class LapProgressResult {
  /// Read-throughs created by this marking, testament first. Empty when the
  /// marking finished nothing.
  final List<ReadThrough> completed;

  /// The lap state after the marking, with any completed testament cleared.
  final LapCoverage coverage;

  const LapProgressResult({required this.completed, required this.coverage});

  bool get isMilestone => completed.isNotEmpty;
}

/// Accumulates the chapters a user marks into their current testament laps and
/// detects the moment a lap completes.
///
/// Detection runs here, on the marking user's own device, because a group
/// schedule is a shared *assignment*, never shared *marking* — nobody else can
/// change a user's coverage, so no server-side trigger is needed.
class LapProgressService {
  LapProgressService({
    FirebaseFirestore? firestore,
    ReadThroughService? readThroughService,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        readThroughService = readThroughService ??
            ReadThroughService(
              firestore: firestore ?? FirebaseFirestore.instance,
            );

  final FirebaseFirestore firestore;
  final ReadThroughService readThroughService;

  static const String _collection = 'read_through_state';
  static const String _docId = 'current';

  DocumentReference<Map<String, dynamic>> _ref(String uid) => firestore
      .collection('users')
      .doc(uid)
      .collection(_collection)
      .doc(_docId);

  /// The user's current lap coverage.
  Future<LapCoverage> fetch(String uid) async {
    final doc = await _ref(uid).get();
    return LapCoverage.fromMap(doc.data());
  }

  /// Streams the user's current lap coverage.
  Stream<LapCoverage> watch(String uid) =>
      _ref(uid).snapshots().map((doc) => LapCoverage.fromMap(doc.data()));

  /// Credits [references] to the current laps and settles anything they
  /// finished.
  ///
  /// References are chapter-level ("Genesis 1"); unparseable ones are ignored.
  /// When a testament completes, its read-through is recorded, any whole Bible
  /// it pairs into is derived, and that testament's lap starts over.
  Future<LapProgressResult> recordChapters(
    String uid,
    Iterable<String> references, {
    DateTime? completedAt,
  }) async {
    final chapters = chaptersFrom(references);
    var coverage = (await fetch(uid)).plus(chapters);

    final completed = <ReadThrough>[];
    for (final scope in const [
      ReadThroughScope.oldTestament,
      ReadThroughScope.newTestament,
    ]) {
      if (!coverage.isComplete(scope)) continue;
      completed.addAll(
        await readThroughService.recordDetected(
          uid: uid,
          scope: scope,
          completedAt: completedAt ?? DateTime.now(),
        ),
      );
      coverage = coverage.cleared(scope);
    }

    await _ref(uid).set(coverage.toMap());
    return LapProgressResult(completed: completed, coverage: coverage);
  }

  /// Seeds the current laps from a user's lifetime coverage.
  ///
  /// Used once, when read-throughs ship: existing progress becomes lap 1 in
  /// progress rather than being zeroed out. Any testament already covered in
  /// full is granted a silent, backdated read-through and its lap starts over.
  Future<LapProgressResult> seedFromLifetime(
    String uid,
    Map<String, Set<int>> lifetimeCoverage, {
    DateTime? asOf,
  }) async {
    var coverage = LapCoverage.empty.plus(lifetimeCoverage);

    final granted = <ReadThrough>[];
    for (final scope in const [
      ReadThroughScope.oldTestament,
      ReadThroughScope.newTestament,
    ]) {
      if (!coverage.isComplete(scope)) continue;
      granted.addAll(
        await readThroughService.addBackfilled(
          uid: uid,
          scope: scope,
          completedAt: asOf ?? DateTime.now(),
          precision: DatePrecision.day,
          source: ReadThroughSource.migrated,
        ),
      );
      coverage = coverage.cleared(scope);
    }

    await _ref(uid).set(coverage.toMap());
    return LapProgressResult(completed: granted, coverage: coverage);
  }

  /// Whether this user has been seeded yet.
  Future<bool> isSeeded(String uid) async => (await _ref(uid).get()).exists;

  /// Parses chapter references into a book-to-chapters map, dropping anything
  /// that does not resolve to a real chapter.
  static Map<String, Set<int>> chaptersFrom(Iterable<String> references) {
    final result = <String, Set<int>>{};
    for (final reference in references) {
      final parsed = ReferenceParser.parseChapterRef(reference);
      if (parsed == null) continue;
      result.putIfAbsent(parsed.book, () => <int>{}).add(parsed.chapter);
    }
    return result;
  }
}

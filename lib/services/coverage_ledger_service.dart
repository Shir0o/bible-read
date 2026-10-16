import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';

import '../models/group_schedule.dart';
import '../models/lap_coverage.dart';
import '../models/read_through.dart';
import '../models/reading_plan.dart';
import 'bible_progress_service.dart';
import 'error_logger.dart';
import 'lap_progress_service.dart';
import 'milestone_announcer.dart';
import 'read_through_service.dart';
import 'reading_plan_service.dart';
import 'reference_parser.dart';

/// Deep module encapsulating Bible coverage, testament laps, and the read-through
/// ledger across all reading surfaces (group schedules, personal plans, and manual marking).
///
/// Unifies what was previously split between [LapProgressService], [ReadThroughService],
/// [ReadThroughCoordinator], and [BibleProgressService].
class CoverageLedgerService {
  CoverageLedgerService({
    FirebaseFirestore? firestore,
    LapProgressService? lapService,
    ReadThroughService? readThroughService,
    ReadingPlanService? planService,
    MilestoneAnnouncer? announcer,
    BibleProgressService? bibleProgressService,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        _bibleProgressService = bibleProgressService,
        readThroughService = readThroughService ??
            ReadThroughService(
              firestore: firestore ?? FirebaseFirestore.instance,
            ),
        lapService = lapService ??
            LapProgressService(
              firestore: firestore ?? FirebaseFirestore.instance,
              readThroughService: readThroughService ??
                  ReadThroughService(
                    firestore: firestore ?? FirebaseFirestore.instance,
                  ),
            ),
        planService = planService ??
            ReadingPlanService(
              firestore: firestore ?? FirebaseFirestore.instance,
            ),
        announcer = announcer ??
            MilestoneAnnouncer(
              firestore: firestore ?? FirebaseFirestore.instance,
            );

  final FirebaseFirestore firestore;
  final LapProgressService lapService;
  final ReadThroughService readThroughService;
  final ReadingPlanService planService;
  final MilestoneAnnouncer announcer;
  BibleProgressService? _bibleProgressService;

  BibleProgressService get bibleProgressService =>
      _bibleProgressService ??= BibleProgressService(firestore: firestore);

  // ---------------------------------------------------------------------------
  // Chapter Crediting
  // ---------------------------------------------------------------------------

  /// Credits [references] to the current testament laps and settles any read-throughs
  /// they finish.
  ///
  /// When [silent] is false and a lap finishes, announces the milestone to the feed.
  /// When [silent] is true (e.g. Starting point or migration), no milestone is announced.
  Future<LapProgressResult> creditChapters(
    String uid,
    Iterable<String> references, {
    bool silent = false,
    DateTime? completedAt,
  }) async {
    final refsList = references.toList();
    if (refsList.isEmpty) {
      final current = await fetchLapCoverage(uid);
      return LapProgressResult(completed: const [], coverage: current);
    }
    final result = await lapService.recordChapters(
      uid,
      refsList,
      completedAt: completedAt,
    );
    if (!silent && result.isMilestone) {
      try {
        await announcer.announce(uid: uid, completed: result.completed);
      } catch (e, st) {
        ErrorLogger.log(e, st);
      }
    }
    return result;
  }

  /// Credits the chapters a user just checked off in a group schedule.
  ///
  /// [checkedIndices] indexes into [schedule].chapters.
  Future<void> creditGroupReading({
    required String uid,
    required GroupSchedule schedule,
    required Iterable<int> checkedIndices,
    bool silent = false,
  }) async {
    final chapters = schedule.chapters;
    if (chapters.isEmpty) return;

    final references = <String>[];
    for (final index in checkedIndices) {
      if (index < 0 || index >= chapters.length) continue;
      references.add(chapters[index]);
    }
    if (references.isEmpty) return;
    try {
      await creditChapters(uid, references, silent: silent);
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  /// Credits every chapter scheduled for [day] of [planId].
  Future<void> creditPlanDay({
    required String uid,
    required String planId,
    required int day,
    bool silent = false,
  }) async {
    try {
      final plan = await planService.getPlanById(planId, userId: uid);
      if (plan == null) return;
      final readings = _readingsForDay(plan, day);
      if (readings.isEmpty) return;
      await creditChapters(uid, readings, silent: silent);
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  /// Credits [day] of [planId] silently without milestone announcement (ADR-0005).
  Future<void> creditPlanDaySilently({
    required String uid,
    required String planId,
    required int day,
  }) =>
      creditPlanDay(uid: uid, planId: planId, day: day, silent: true);

  static List<String> _readingsForDay(ReadingPlan plan, int day) {
    for (final entry in plan.schedule) {
      if (entry.day == day) return entry.readings;
    }
    return const [];
  }

  // ---------------------------------------------------------------------------
  // Lap Coverage
  // ---------------------------------------------------------------------------

  /// Streams the user's current lap coverage.
  Stream<LapCoverage> watchLapCoverage(String uid) => lapService.watch(uid);

  /// Fetches the user's current lap coverage.
  Future<LapCoverage> fetchLapCoverage(String uid) => lapService.fetch(uid);

  /// Seeds current laps from lifetime coverage (one-time migration helper).
  Future<LapProgressResult> seedFromLifetime(
    String uid,
    Map<String, Set<int>> lifetimeCoverage, {
    DateTime? asOf,
  }) =>
      lapService.seedFromLifetime(uid, lifetimeCoverage, asOf: asOf);

  /// Whether this user has been seeded into the lap model yet.
  Future<bool> isSeeded(String uid) => lapService.isSeeded(uid);

  // ---------------------------------------------------------------------------
  // Read-Throughs & Counts
  // ---------------------------------------------------------------------------

  /// Streams all read-through records for [uid], oldest first with lap numbers.
  Stream<List<ReadThrough>> watchReadThroughs(String uid) =>
      readThroughService.watch(uid);

  /// Fetches all read-through records for [uid], oldest first with lap numbers.
  Future<List<ReadThrough>> fetchReadThroughs(String uid) =>
      readThroughService.fetchAll(uid);

  /// Streams the user's read-through counts.
  Stream<ReadThroughCounts> watchCounts(String uid) =>
      watchReadThroughs(uid).map(ReadThroughService.countsFrom);

  /// Fetches the user's current read-through counts.
  Future<ReadThroughCounts> fetchCounts(String uid) async {
    final rows = await fetchReadThroughs(uid);
    return ReadThroughService.countsFrom(rows);
  }

  /// Records the app has not yet celebrated, oldest first.
  Future<List<ReadThrough>> uncelebrated(String uid) =>
      readThroughService.uncelebrated(uid);

  /// Marks records as celebrated so celebration modal never replays.
  Future<void> markCelebrated(String uid, Iterable<String> ids) =>
      readThroughService.markCelebrated(uid, ids);

  /// Adds a read-through entered by hand.
  Future<List<ReadThrough>> addBackfilled({
    required String uid,
    required ReadThroughScope scope,
    required DateTime completedAt,
    required DatePrecision precision,
    String location = '',
    ReadThroughSource source = ReadThroughSource.backfilled,
  }) =>
      readThroughService.addBackfilled(
        uid: uid,
        scope: scope,
        completedAt: completedAt,
        precision: precision,
        location: location,
        source: source,
      );

  /// Edits user-supplied fields of a read-through row.
  Future<void> updateReadThroughDetails(
    String uid,
    String id, {
    DateTime? completedAt,
    DatePrecision? datePrecision,
    String? location,
  }) =>
      readThroughService.updateDetails(
        uid,
        id,
        completedAt: completedAt,
        datePrecision: datePrecision,
        location: location,
      );

  /// Deletes a hand-entered record, reconciling any derived Bible records.
  Future<void> deleteReadThrough(String uid, String id) =>
      readThroughService.delete(uid, id);

  // ---------------------------------------------------------------------------
  // Book & Lifetime Chapter Coverage
  // ---------------------------------------------------------------------------

  /// Aggregates completed chapters by canonical book name across:
  /// 1. Legacy group schedule entries
  /// 2. Current lap chapters (including personal plans and group readings)
  /// 3. Completed read-throughs from ledger (earlier laps)
  /// 4. Manual book completions in users/{uid}/bible_books
  Future<Map<String, Set<int>>> completedChaptersByBook(String uid) async {
    Map<String, Set<int>> legacy = const {};
    try {
      legacy = await bibleProgressService.completedChaptersByBook(uid);
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }

    LapCoverage lap = LapCoverage.empty;
    try {
      lap = await fetchLapCoverage(uid);
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }

    List<ReadThrough> readThroughs = const [];
    try {
      readThroughs = await fetchReadThroughs(uid);
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }

    Set<String> manualBooks = const {};
    try {
      final snap = await firestore
          .collection('users')
          .doc(uid)
          .collection('bible_books')
          .get();
      manualBooks = snap.docs.map((d) => d.id).toSet();
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }

    return unifyCoverage(
      baseGroupCoverage: legacy,
      lapCoverage: lap,
      readThroughs: readThroughs,
      manualBooks: manualBooks,
    );
  }

  /// Reactive stream of lifetime chapter coverage by book, unifying current lap,
  /// completed read-throughs, and manual completions.
  Stream<Map<String, Set<int>>> watchBookCoverage(String uid) {
    final manualBooksStream = firestore
        .collection('users')
        .doc(uid)
        .collection('bible_books')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => doc.id).toSet())
        .startWith(const <String>{});

    return Rx.defer(() {
      return Stream.fromFuture(
        bibleProgressService
            .completedChaptersByBook(uid)
            .catchError((Object e, StackTrace st) {
          ErrorLogger.log(e, st);
          return <String, Set<int>>{};
        }),
      ).switchMap((baseGroup) {
        return Rx.combineLatest3<LapCoverage, List<ReadThrough>, Set<String>,
            Map<String, Set<int>>>(
          watchLapCoverage(uid),
          watchReadThroughs(uid),
          manualBooksStream,
          (lap, readThroughs, manualBooks) {
            return unifyCoverage(
              baseGroupCoverage: baseGroup,
              lapCoverage: lap,
              readThroughs: readThroughs,
              manualBooks: manualBooks,
            );
          },
        );
      });
    });
  }

  /// Pure unification of coverage across all sources.
  static Map<String, Set<int>> unifyCoverage({
    Map<String, Set<int>>? baseGroupCoverage,
    required LapCoverage lapCoverage,
    required List<ReadThrough> readThroughs,
    Set<String>? manualBooks,
  }) {
    final result = <String, Set<int>>{};

    // 1. Base group progress (group schedules, etc.)
    if (baseGroupCoverage != null) {
      baseGroupCoverage.forEach((book, chapters) {
        if (chapters.isNotEmpty) {
          result[book] = Set<int>.from(chapters);
        }
      });
    }

    // 2. Current lap coverage (from personal plans, group readings, etc.)
    for (final entry in lapCoverage.oldTestament.entries) {
      if (entry.value.isNotEmpty) {
        result.putIfAbsent(entry.key, () => <int>{}).addAll(entry.value);
      }
    }
    for (final entry in lapCoverage.newTestament.entries) {
      if (entry.value.isNotEmpty) {
        result.putIfAbsent(entry.key, () => <int>{}).addAll(entry.value);
      }
    }

    // 3. Completed read-throughs from ledger
    // A reader who has completed a testament at least once has read every chapter
    // of every book in that testament.
    final hasOt = readThroughs.any((r) =>
        r.scope == ReadThroughScope.oldTestament ||
        r.scope == ReadThroughScope.wholeBible);
    final hasNt = readThroughs.any((r) =>
        r.scope == ReadThroughScope.newTestament ||
        r.scope == ReadThroughScope.wholeBible);

    if (hasOt) {
      for (final book in LapCoverage.otBooks) {
        final count = ReferenceParser.chapterCount(book) ?? 0;
        if (count > 0) {
          result[book] = Set<int>.from(List.generate(count, (i) => i + 1));
        }
      }
    }

    if (hasNt) {
      for (final book in LapCoverage.ntBooks) {
        final count = ReferenceParser.chapterCount(book) ?? 0;
        if (count > 0) {
          result[book] = Set<int>.from(List.generate(count, (i) => i + 1));
        }
      }
    }

    // 4. Manual book completions
    if (manualBooks != null) {
      for (final book in manualBooks) {
        final count = ReferenceParser.chapterCount(book) ?? 0;
        if (count > 0) {
          result[book] = Set<int>.from(List.generate(count, (i) => i + 1));
        }
      }
    }

    return result.map(
      (book, chapters) => MapEntry(book, Set<int>.unmodifiable(chapters)),
    );
  }

  // ---------------------------------------------------------------------------
  // Manual Book Helpers
  // ---------------------------------------------------------------------------

  /// Returns the name of the book most recently marked as completed by [uid].
  Future<String?> getLastCheckedBook(String uid) async {
    try {
      final snap = await firestore
          .collection('users')
          .doc(uid)
          .collection('bible_books')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        return snap.docs.first.id;
      }
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
    return null;
  }

  /// Sets or clears a manual book completion in users/{uid}/bible_books.
  /// When [completed] is true, also credits the book's chapters to the current lap.
  Future<void> setBookManualCompletion({
    required String uid,
    required String book,
    required bool completed,
  }) async {
    final ref = firestore
        .collection('users')
        .doc(uid)
        .collection('bible_books')
        .doc(book);

    if (completed) {
      await ref.set({
        'completed': true,
        'timestamp': FieldValue.serverTimestamp(),
      });

      final total = ReferenceParser.chapterCount(book) ?? 0;
      if (total > 0) {
        await creditChapters(
          uid,
          List<String>.generate(total, (i) => '$book ${i + 1}'),
        );
      }
    } else {
      await ref.delete();
    }
  }
}

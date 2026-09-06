import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/read_through.dart';
import '../services/bible_progress_service.dart';
import '../services/error_logger.dart';
import '../services/lap_progress_service.dart';
import '../services/read_through_service.dart';
import '../services/vibration_service.dart';
import 'read_through_celebration.dart';

/// Watches the signed-in user's read-throughs and shows the celebration for
/// any that have not been celebrated yet.
///
/// Detection happens wherever the user marked — this is what turns a detected
/// record into the moment. Reading from the uncelebrated queue rather than
/// firing at the call site means the celebration survives the app being closed
/// between the marking and the next launch.
class ReadThroughHost extends StatefulWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final Widget child;
  final ReadThroughService? service;
  final LapProgressService? lapService;
  final BibleProgressService? bibleProgressService;
  final VibrationService vibrationService;

  /// Opened from the celebration's "Add where you were" button.
  final void Function(ReadThrough readThrough)? onAddLocation;

  const ReadThroughHost({
    super.key,
    required this.auth,
    required this.firestore,
    required this.child,
    this.service,
    this.lapService,
    this.bibleProgressService,
    this.vibrationService = const VibrationService(),
    this.onAddLocation,
  });

  @override
  State<ReadThroughHost> createState() => _ReadThroughHostState();
}

class _ReadThroughHostState extends State<ReadThroughHost> {
  late final ReadThroughService _service;
  late final LapProgressService _laps;
  StreamSubscription<List<ReadThrough>>? _subscription;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _service =
        widget.service ?? ReadThroughService(firestore: widget.firestore);
    _laps = widget.lapService ??
        LapProgressService(
          firestore: widget.firestore,
          readThroughService: _service,
        );
    unawaited(_seedOnce());
    _listen();
  }

  /// Carries a user's existing progress into the lap model, once.
  ///
  /// Without this, everyone's Bible Library would reset to empty the day
  /// read-throughs ship. Anything already covered in full is granted a
  /// backdated read-through, which is deliberately silent: a migration is not
  /// an event, and celebrating it would greet every long-time reader with a
  /// party for something they did years ago.
  Future<void> _seedOnce() async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    try {
      if (await _laps.isSeeded(user.uid)) return;
      final lifetime = await (widget.bibleProgressService ??
              BibleProgressService(firestore: widget.firestore))
          .completedChaptersByBook(user.uid);
      await _laps.seedFromLifetime(user.uid, lifetime);
    } catch (e, st) {
      ErrorLogger.log(e, st);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _listen() {
    final user = widget.auth.currentUser;
    if (user == null) return;
    _subscription = _service.watch(user.uid).listen(
          _onLedger,
          onError: (Object e, StackTrace st) => ErrorLogger.log(e, st),
        );
  }

  Future<void> _onLedger(List<ReadThrough> rows) async {
    if (_showing || !mounted) return;

    // Backfilled and migrated records are born celebrated, so anything left
    // here is something that just happened.
    final pending = rows.where((r) => !r.celebrated).toList();
    if (pending.isEmpty) return;

    // One celebration per marking: everything a single marking produced shares
    // the same completion moment.
    final moment = pending.first.completedAt;
    final batch = pending
        .where((r) => r.completedAt.difference(moment).abs().inMinutes < 1)
        .toList()
      ..sort((a, b) => a.scope.index.compareTo(b.scope.index));

    _showing = true;
    try {
      await _present(batch, ReadThroughService.countsFrom(rows));
      await _service.markCelebrated(
        widget.auth.currentUser!.uid,
        batch.map((r) => r.id),
      );
    } catch (e, st) {
      ErrorLogger.log(e, st);
    } finally {
      _showing = false;
    }
  }

  Future<void> _present(
    List<ReadThrough> batch,
    ReadThroughCounts counts,
  ) async {
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final onAddLocation = widget.onAddLocation;

    await navigator.push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (context, animation, _) => FadeTransition(
          opacity: animation,
          child: ReadThroughCelebration(
            completed: batch,
            counts: counts,
            vibrationService: widget.vibrationService,
            onDismiss: () => Navigator.of(context).pop(),
            onAddLocation: onAddLocation == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    onAddLocation(batch.last);
                  },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

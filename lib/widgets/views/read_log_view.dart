import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../services/error_logger.dart';
import '../../services/vibration_service.dart';

import '../common_styles.dart';
import '../read_log_list.dart';
import '../../services/reading_status_service.dart';
import '../../services/read_log_service.dart';

import '../../models/read_log.dart';
import '../skeleton_loader.dart';
import '../skeletons/read_log_skeleton.dart';
import '../skeletons/read_log_empty_skeleton.dart';

class ReadLogView extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final ReadingStatusService readingStatusService;
  final Future<void> Function({
    required String ownerUid,
    required String likerName,
  }) onSendLikeNotification;
  final DateTime Function() dateProvider;
  final VibrationService? vibrationService;

  ReadLogView({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    required this.readingStatusService,
    required this.onSendLikeNotification,
    DateTime Function()? dateProvider,
    this.tabController,
    this.vibrationService,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance,
        dateProvider = dateProvider ?? DateTime.now;

  final TabController? tabController;

  @override
  State<ReadLogView> createState() => _ReadLogViewState();
}

class _ReadLogViewState extends State<ReadLogView>
    with AutomaticKeepAliveClientMixin {
  List<ReadLog> _logs = [];
  bool _loading = true;
  bool _loadError = false;
  bool _readToday = true; // Default to true to show list skeleton
  StreamSubscription<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _logsSub;

  Future<void> _sendAmenNotification({
    required String ownerUid,
    required String amenName,
  }) async {
    await widget.onSendLikeNotification(
      ownerUid: ownerUid,
      likerName: amenName,
    );
  }

  @override
  void initState() {
    super.initState();
    _subscribeLogs();
    _checkReadStatus();
  }

  Future<void> _checkReadStatus() async {
    try {
      final status = await widget.readingStatusService.fetchStatus();
      if (mounted) {
        setState(() {
          _readToday = status.readToday;
        });
      }
    } catch (e) {
      // Ignore errors, default to keeping current skeleton
    }
  }

  @override
  void dispose() {
    _logsSub?.cancel();
    super.dispose();
  }

  /// Subscribes to today's per-Group feed (ADR-0004). The stream is live:
  /// a co-member's mark or Amen arrives without a pull-to-refresh, so the
  /// five-minute silent reload path is gone with the one-shot query. Entries
  /// hydrate from their documents — name, timestamp, milestone and Amens —
  /// so a card shows what the entry actually carries.
  void _subscribeLogs() {
    final currentUser = widget.auth.currentUser;
    if (currentUser == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    final dateKey = ReadLogService.dateKeyFor(widget.dateProvider());
    final service = ReadLogService(firestore: widget.firestore);
    _logsSub?.cancel();
    _logsSub = service
        .entryDocsForGroupsForUser(currentUser.uid, dateKey: dateKey)
        .listen(
      (docs) async {
        if (!mounted) return;
        try {
          final logs = await Future.wait([
            for (final doc in docs)
              ReadLog.fromFirestore(doc, currentUid: currentUser.uid),
          ]);
          setState(() {
            _logs = logs;
            _loading = false;
            _loadError = false;
          });
        } catch (e, st) {
          ErrorLogger.log(e, st);
          if (mounted) {
            setState(() {
              _loading = false;
              _loadError = true;
            });
          }
        }
      },
      onError: (e, st) {
        ErrorLogger.log(e, st);
        if (mounted) {
          setState(() {
            _loading = false;
            _loadError = true;
          });
        }
      },
    );
  }

  /// Re-subscribes to the live feed. Kept for the RefreshIndicator path and
  /// the ReadLogPage.refresh() key.
  void refresh() => _subscribeLogs();

  Future<void> _toggleLike(String logUid) async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    final index = _logs.indexWhere((log) => log.uid == logUid);
    if (index == -1) return;
    final original = _logs[index];

    final amenName = (user.displayName ?? '').split(' ').first;
    final now = widget.dateProvider();
    final dateKey = ReadLogService.dateKeyFor(now);
    final service = ReadLogService(firestore: widget.firestore);
    // The liker can only write an Amen inside a Group they belong to (the
    // rules gate this path on membership), and they can only see the entry
    // through those same Groups — so the reader's own Groups locate the
    // entry. Falls back silently when the reader has none.
    final groupIds = await service.groupIdsFor(user.uid);
    if (groupIds.isEmpty) return;
    final amenRef = widget.firestore
        .collection('groups')
        .doc(groupIds.first)
        .collection('read_log')
        .doc(dateKey)
        .collection('entries')
        .doc(logUid)
        .collection('likes')
        .doc(user.uid);

    if (original.liked) {
      // Undo the Amen.
      final updatedNames = List<String>.from(original.likeNames)
        ..remove(amenName);
      setState(() {
        _logs[index] = original.copyWith(liked: false, likeNames: updatedNames);
      });

      try {
        await amenRef.delete();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('Failed to undo Amen: $e');
        }
        ErrorLogger.log(e, st);
        if (mounted) {
          setState(() => _logs[index] = original);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Failed to remove your Amen. Please try again.',
              ),
            ),
          );
        }
      }
    } else {
      // Amen.
      final updatedNames = List<String>.from(original.likeNames)
        ..add(amenName);
      setState(() {
        _logs[index] = original.copyWith(liked: true, likeNames: updatedNames);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Amen sent'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      try {
        final amenDoc = await amenRef.get();
        if (amenDoc.exists) {
          if (mounted) {
            setState(() => _logs[index] = original);
          }
          return;
        }
        await amenRef.set({'timestamp': Timestamp.now(), 'name': amenName});
        if (logUid != user.uid) {
          await _sendAmenNotification(ownerUid: logUid, amenName: amenName);
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('Failed to toggle Amen: $e');
        }
        ErrorLogger.log(e, st);
        if (mounted) {
          setState(() => _logs[index] = original);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to send your Amen. Please try again.'),
            ),
          );
        }
      }
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: Container(
        decoration: CommonStyles.backgroundDecoration(
          Theme.of(context).colorScheme,
        ),
        child: SkeletonLoader(
          loading: _loading,
          skeleton: _readToday
              ? const ReadLogSkeleton()
              : const ReadLogEmptySkeleton(),
          child: _loadError
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text(
                      'Unable to load today\'s readers.\nPlease check your connection.',
                      style: AppTextStyles.body(context).copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : widget.auth.currentUser == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 48,
                              color:
                                  Theme.of(context).colorScheme.outlineVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Sign in to see who\'s reading today',
                              style: AppTextStyles.subtitle(context).copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Join a group and encourage others.',
                              style: AppTextStyles.body(context).copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : _logs.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(48.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.wb_sunny_outlined,
                                  size: 48,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Be the first light today',
                                  style:
                                      AppTextStyles.subtitle(context).copyWith(
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Read your passage and be an encouragement to others.',
                                  style: AppTextStyles.body(context).copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    height: 1.5,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(
                            top: 16.0,
                            bottom: 48.0,
                            left: 16,
                            right: 16,
                          ),
                          child: ReadLogList(
                            logs: _logs,
                            onToggleLike: _toggleLike,
                            vibrationService: widget.vibrationService,
                          ),
                        ),
        ),
      ),
    );
  }
}

typedef ReadLogViewState = _ReadLogViewState;

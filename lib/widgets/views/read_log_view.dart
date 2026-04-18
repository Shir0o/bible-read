import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../services/error_logger.dart';
import '../../services/vibration_service.dart';

import '../common_styles.dart';
import '../../models/comment.dart';
import '../read_log_list.dart';
import '../../services/reading_status_service.dart';
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
  final Future<void> Function({
    required String ownerUid,
    required String commenterName,
  }) onSendCommentNotification;
  final DateTime Function() dateProvider;
  final VibrationService? vibrationService;

  ReadLogView({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    required this.readingStatusService,
    required this.onSendLikeNotification,
    required this.onSendCommentNotification,
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
  DateTime? _lastLoadTime;

  Future<void> _sendLikeNotification({
    required String ownerUid,
    required String likerName,
  }) async {
    await widget.onSendLikeNotification(
      ownerUid: ownerUid,
      likerName: likerName,
    );
  }

  Future<void> _sendCommentNotification({
    required String ownerUid,
    required String commenterName,
  }) async {
    await widget.onSendCommentNotification(
      ownerUid: ownerUid,
      commenterName: commenterName,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.tabController?.addListener(_onTabChanged);
    _loadLogs();
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
    widget.tabController?.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (widget.tabController?.index == 1) {
      // We are on the Feed tab (index 1)
      final now = DateTime.now();
      if (_lastLoadTime != null &&
          now.difference(_lastLoadTime!) > const Duration(minutes: 5)) {
        _loadLogs(silent: true);
      }
    }
  }

  Future<void> _loadLogs({bool silent = false}) async {
    final currentUser = widget.auth.currentUser;
    if (currentUser == null) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
      return;
    }

    if (!silent) {
      setState(() {
        _loading = true;
        _loadError = false;
      });
    }
    bool error = false;
    List<ReadLog> logs = [];
    try {
      final now = widget.dateProvider();
      final dateKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final snapshot = await widget.firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .orderBy('timestamp', descending: true)
          .get();
      String? firstReaderUid;
      try {
        final rewardDoc = await widget.firestore
            .collection('daily_rewards')
            .doc(dateKey)
            .get();
        firstReaderUid = rewardDoc.data()?['uid'] as String?;
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('Load daily reward failed: $e');
        }
        ErrorLogger.log(e, st);
        firstReaderUid = null;
      }

      logs = await Future.wait(
        snapshot.docs.map((doc) {
          return ReadLog.fromFirestore(
            doc,
            currentUid: currentUser.uid,
            firstReaderUid: firstReaderUid,
          );
        }).toList(),
      );
      _lastLoadTime = DateTime.now();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Load logs failed: $e');
      }
      ErrorLogger.log(e, st);
      error = true;
    } finally {
      setState(() {
        if (!error) {
          _logs = logs;
        }
        _loading = false;
        _loadError = error;
      });
    }
  }

  /// Reloads the read log entries.
  Future<void> refresh() => _loadLogs();

  Future<void> _toggleLike(String logUid) async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    final index = _logs.indexWhere((log) => log.uid == logUid);
    if (index == -1) return;
    final original = _logs[index];

    final likerName = (user.displayName ?? '').split(' ').first;
    final now = widget.dateProvider();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final likeRef = widget.firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc(logUid)
        .collection('likes')
        .doc(user.uid);

    if (original.liked) {
      // Unlike logic
      final updatedNames = List<String>.from(original.likeNames)
        ..remove(likerName);
      setState(() {
        _logs[index] = original.copyWith(liked: false, likeNames: updatedNames);
      });

      try {
        await likeRef.delete();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('Failed to unlike: $e');
        }
        ErrorLogger.log(e, st);
        if (mounted) {
          setState(() => _logs[index] = original);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Failed to remove encouragement. Please try again.')),
          );
        }
      }
    } else {
      // Like logic
      final updatedNames = List<String>.from(original.likeNames)
        ..add(likerName);
      setState(() {
        _logs[index] = original.copyWith(liked: true, likeNames: updatedNames);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Encouragement sent'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      try {
        final likeDoc = await likeRef.get();
        if (likeDoc.exists) {
          if (mounted) {
            setState(() => _logs[index] = original);
          }
          return;
        }
        await likeRef.set({'timestamp': Timestamp.now(), 'name': likerName});
        if (logUid != user.uid) {
          await _sendLikeNotification(ownerUid: logUid, likerName: likerName);
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('Failed to toggle like: $e');
        }
        ErrorLogger.log(e, st);
        if (mounted) {
          setState(() => _logs[index] = original);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Failed to encourage. Please try again.')),
          );
        }
      }
    }
  }

  Future<Comment> _addComment(String logUid, String message) async {
    final user = widget.auth.currentUser;
    if (user == null) {
      throw StateError('User not signed in');
    }
    final index = _logs.indexWhere((log) => log.uid == logUid);
    if (index == -1) {
      throw StateError('Log not found');
    }

    final author = (user.displayName ?? '').split(' ').first;
    final comment = Comment(
      id: '',
      uid: user.uid,
      authorName: author,
      message: message,
      timestamp: DateTime.now(),
    );

    final original = _logs[index];
    final originalComments = List<Comment>.from(original.comments);
    setState(() {
      _logs[index] = original.copyWith(
        comments: [...originalComments, comment],
      );
    });

    final now = widget.dateProvider();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final commentsRef = widget.firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc(logUid)
        .collection('comments');
    try {
      final docRef = await commentsRef.add(comment.toFirestore());
      
      await widget.firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc(logUid)
          .update({'lastActivityAt': FieldValue.serverTimestamp()});
      Comment persisted = Comment(
        id: docRef.id,
        uid: comment.uid,
        authorName: comment.authorName,
        message: comment.message,
        timestamp: comment.timestamp,
      );
      if (mounted) {
        final updated = List<Comment>.from(originalComments)..add(persisted);
        setState(() {
          _logs[index] = original.copyWith(comments: updated);
        });
      }
      if (logUid != user.uid) {
        await _sendCommentNotification(ownerUid: logUid, commenterName: author);
      }
      return persisted;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to add comment: $e');
      }
      ErrorLogger.log(e, st);
      if (mounted) {
        setState(() {
          _logs[index] = original;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add comment. Please try again.'),
          ),
        );
      }
      rethrow;
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: Container(
        decoration:
            CommonStyles.backgroundDecoration(Theme.of(context).colorScheme),
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
                              'Join the community and encourage others.',
                              style: AppTextStyles.body(context).copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
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
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
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
                            onAddComment: _addComment,
                            commenterName:
                                (widget.auth.currentUser?.displayName ?? '')
                                    .split(' ')
                                    .first,
                            vibrationService: widget.vibrationService,
                          ),
                        ),
        ),
      ),
    );
  }
}

typedef ReadLogViewState = _ReadLogViewState;

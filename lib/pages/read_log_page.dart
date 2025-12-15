import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../services/error_logger.dart';

import '../services/achievement_service.dart';
import '../models/achievement.dart';

import '../widgets/common_styles.dart';
import '../models/comment.dart';
import '../widgets/read_log_list.dart';
import '../models/read_log.dart';

class ReadLogPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final Future<void> Function({
    required String ownerUid,
    required String likerName,
  }) onSendLikeNotification;
  final Future<void> Function({
    required String ownerUid,
    required String commenterName,
  }) onSendCommentNotification;
  final DateTime Function() dateProvider;

  ReadLogPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    required this.onSendLikeNotification,
    required this.onSendCommentNotification,
    DateTime Function()? dateProvider,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance,
        dateProvider = dateProvider ?? DateTime.now;

  @override
  State<ReadLogPage> createState() => _ReadLogPageState();

  static Future<void> writeReadLogEntry(
    User user, {
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    Future<Map<String, dynamic>?> Function({
      required String dateKey,
      required String uid,
    })? markFirstReader,
    DateTime Function()? dateProvider,
  }) async {
    final db = firestore ?? FirebaseFirestore.instance;
    final now = (dateProvider ?? DateTime.now)();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await db
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc(user.uid)
        .set({
      'name': (user.displayName ?? '').split(' ').first,
      'email': user.email?.toLowerCase() ?? '',
      'timestamp': Timestamp.now(),
    });

    // Keep the per-user reading collection in sync for streak calculations.
    try {
      await db
          .collection('users')
          .doc(user.uid)
          .collection('reading')
          .doc(dateKey)
          .set({'read': true}, SetOptions(merge: true));
    } catch (_) {
      // Best effort: ignore failures here since the log entry itself succeeded.
    }
    final handler = markFirstReader;
    Map<String, dynamic>? result;
    if (handler != null) {
      result = await handler(dateKey: dateKey, uid: user.uid);
    } else if (functions != null) {
      try {
        final res = await functions.httpsCallable('markFirstReader').call({
          'dateKey': dateKey,
        });
        if (res.data is Map) {
          result = Map<String, dynamic>.from(res.data as Map);
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('markFirstReader failed: $e');
        }
        ErrorLogger.log(e, st);
      }
    }

    if (result?['first'] == true) {
      await AchievementService(firestore: db).unlockAchievement(
        user.uid,
        Achievement(
          id: 'firstReader',
          title: 'First Reader',
          type: 'first',
          dateUnlocked: DateTime.now(),
        ),
      );
    }
  }
}

class _ReadLogPageState extends State<ReadLogPage> {
  List<ReadLog> _logs = [];
  bool _loading = true;
  bool _loadError = false;

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
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final currentUser = widget.auth.currentUser;
    if (currentUser == null) {
      setState(() {
        _loading = false;
      });
      return;
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

    if (original.liked) {
      return;
    }

    final likerName = (user.displayName ?? '').split(' ').first;
    final updatedNames = List<String>.from(original.likeNames)..add(likerName);

    // Optimistically update UI
    setState(() {
      _logs[index] = original.copyWith(liked: true, likeNames: updatedNames);
    });

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
          const SnackBar(content: Text('Failed to like. Please try again.')),
        );
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        context,
        "Today's Readers",
        automaticallyImplyLeading: false,
      ),
      body: Container(
        decoration:
            CommonStyles.backgroundDecoration(Theme.of(context).colorScheme),
        child: _loading
            ? Container(
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              )
            : _loadError
                ? Center(
                    child: Text(
                      'Unable to load feed.',
                      style: AppTextStyles.subtitle
                          .copyWith(color: Colors.white70),
                    ),
                  )
                : widget.auth.currentUser == null
                    ? Center(
                        child: Text(
                          'Please sign in to view your read log.',
                          style: AppTextStyles.subtitle
                              .copyWith(color: Colors.white70),
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
                        ),
                      ),
      ),
    );
  }
}

typedef ReadLogPageState = _ReadLogPageState;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../services/error_logger.dart';

import '../services/achievement_service.dart';
import '../models/achievement.dart';

import '../widgets/common_styles.dart';
import '../widgets/notification_button.dart';
import '../services/notification_service.dart';
import '../widgets/badge_icon.dart';
import '../widgets/comment_section.dart';
import '../widgets/comment_drawer.dart';
import '../widgets/menu_button.dart';
import '../models/comment.dart';

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
    final dateKey = '${now.year}-${now.month}-${now.day}';
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
    final handler = markFirstReader;
    Map<String, dynamic>? result;
    if (handler != null) {
      result = await handler(dateKey: dateKey, uid: user.uid);
    } else if (functions != null) {
      try {
        final res = await functions
            .httpsCallable('markFirstReader')
            .call({'dateKey': dateKey});
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
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  bool _loadError = false;

  Future<void> _sendLikeNotification(
      {required String ownerUid, required String likerName}) async {
    await widget.onSendLikeNotification(
      ownerUid: ownerUid,
      likerName: likerName,
    );
  }

  Future<void> _sendCommentNotification(
      {required String ownerUid, required String commenterName}) async {
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
    List<Map<String, dynamic>> logs = [];
    try {
      final now = widget.dateProvider();
      final dateKey = '${now.year}-${now.month}-${now.day}';
      final snapshot = await widget.firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .orderBy('timestamp', descending: true)
          .get();

      final rewardDoc =
          await widget.firestore.collection('daily_rewards').doc(dateKey).get();
      final firstReaderUid = rewardDoc.data()?['uid'] as String?;

      logs = await Future.wait(snapshot.docs.map((doc) async {
        final data = doc.data();
        final likesSnapshot = await doc.reference.collection('likes').get();
        final likeDocs = likesSnapshot.docs;
        final liked = likeDocs.any((d) => d.id == currentUser.uid);
        final likeNames = likeDocs
            .map((d) => (d.data()['name'] ?? 'Unknown').toString())
            .toList();
        final commentsSnap = await doc.reference
            .collection('comments')
            .orderBy('timestamp')
            .get();
        final comments =
            commentsSnap.docs.map((d) => Comment.fromFirestore(d)).toList();
        return {
          'uid': doc.id,
          'name': (data['name'] ?? doc.id).toString().split(' ').first,
          'read': true,
          'liked': liked,
          'likeNames': likeNames,
          'firstReader': firstReaderUid != null && doc.id == firstReaderUid,
          'comments': comments,
        };
      }).toList());
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

  Future<void> _toggleLike(String logUid) async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    final index = _logs.indexWhere((log) => log['uid'] == logUid);
    if (index == -1) return;
    final original = Map<String, dynamic>.from(_logs[index]);

    if (original['liked'] == true) {
      return;
    }

    final likerName = (user.displayName ?? '').split(' ').first;
    final updatedNames = List<String>.from(original['likeNames'] ?? [])
      ..add(likerName);

    // Optimistically update UI
    setState(() {
      _logs[index] = {
        ...original,
        'liked': true,
        'likeNames': updatedNames,
      };
    });

    final now = widget.dateProvider();
    final dateKey = '${now.year}-${now.month}-${now.day}';
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
      await likeRef.set({
        'timestamp': Timestamp.now(),
        'name': likerName,
      });
      if (logUid != user.uid) {
        await _sendLikeNotification(
          ownerUid: logUid,
          likerName: likerName,
        );
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
    final index = _logs.indexWhere((log) => log['uid'] == logUid);
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

    final originalComments =
        List<Comment>.from(_logs[index]['comments'] as List<Comment>? ?? []);
    setState(() {
      _logs[index] = {
        ..._logs[index],
        'comments': [...originalComments, comment],
      };
    });

    final now = widget.dateProvider();
    final dateKey = '${now.year}-${now.month}-${now.day}';
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
          _logs[index] = {
            ..._logs[index],
            'comments': updated,
          };
        });
      }
      if (logUid != user.uid) {
        await _sendCommentNotification(
          ownerUid: logUid,
          commenterName: author,
        );
      }
      return persisted;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to add comment: $e');
      }
      ErrorLogger.log(e, st);
      if (mounted) {
        setState(() {
          _logs[index] = {
            ..._logs[index],
            'comments': originalComments,
          };
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to add comment. Please try again.')),
        );
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        "Today's Readers",
        leading: const MenuButton(),
        automaticallyImplyLeading: false,
        actions: [
          if (widget.auth.currentUser != null)
            NotificationButton(
              service: NotificationService(firestore: widget.firestore),
              auth: widget.auth,
            ),
        ],
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
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
                            top: 16.0, bottom: 48.0, left: 16, right: 16),
                        child: ListView.builder(
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                            final log = _logs[index];
                            final isLiked = (log['liked'] as bool? ?? false);
                            final isFirst =
                                (log['firstReader'] as bool? ?? false);
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ListTile(
                                      leading: const Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                      ),
                                      title: Text(
                                        '${log['name']} read today!',
                                        style: AppTextStyles.subtitle,
                                      ),
                                      subtitle: () {
                                        final likeNames =
                                            (log['likeNames'] as List?) ?? [];
                                        if (likeNames.isEmpty) return null;

                                        const maxToShow = 3;
                                        final displayText = likeNames.length >
                                                maxToShow
                                            ? '${likeNames.take(maxToShow).join(", ")} +${likeNames.length - maxToShow} more'
                                            : likeNames.join(", ");

                                        return Text('Liked by $displayText');
                                      }(),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isFirst)
                                            const BadgeIcon(
                                              assetPath:
                                                  'assets/achievements/first_reader.png',
                                              size: 24,
                                            ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 4.0),
                                            child: IconButton(
                                              icon: AnimatedSwitcher(
                                                duration: const Duration(
                                                    milliseconds: 300),
                                                transitionBuilder:
                                                    (child, animation) =>
                                                        ScaleTransition(
                                                            scale: animation,
                                                            child: child),
                                                child: Icon(
                                                  isLiked
                                                      ? Icons.favorite
                                                      : Icons.favorite_border,
                                                  key: ValueKey<bool>(isLiked),
                                                  color: isLiked
                                                      ? Colors.red
                                                      : null,
                                                ),
                                              ),
                                              onPressed: isLiked
                                                  ? null
                                                  : () {
                                                      _toggleLike(log['uid']);
                                                    },
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                                Icons.mode_comment_outlined),
                                            onPressed: () {
                                              final commenter = (widget
                                                          .auth
                                                          .currentUser
                                                          ?.displayName ??
                                                      '')
                                                  .split(' ')
                                                  .first;
                                              CommentDrawer.show(
                                                context,
                                                comments: List<Comment>.from(
                                                    log['comments']
                                                        as List<Comment>),
                                                onAdd: (msg) => _addComment(
                                                    log['uid'], msg),
                                                commenterName: commenter,
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    CommentSection(
                                      comments: List<Comment>.from(
                                          log['comments'] as List<Comment>),
                                      onAdd: (msg) =>
                                          _addComment(log['uid'], msg),
                                      showInput: false,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
  }
}

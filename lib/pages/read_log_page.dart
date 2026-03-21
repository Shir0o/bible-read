import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../services/error_logger.dart';

import '../services/reading_status_service.dart';

import '../services/vibration_service.dart';

import '../widgets/common_styles.dart';
import '../widgets/views/read_log_view.dart';

class ReadLogPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final ReadingStatusService? readingStatusService;
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

  ReadLogPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    this.readingStatusService,
    required this.onSendLikeNotification,
    required this.onSendCommentNotification,
    DateTime Function()? dateProvider,
    this.vibrationService,
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
      'uid': user.uid,
      'timestamp': Timestamp.now(),
      'dateId': dateKey,
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
    if (handler != null) {
      await handler(dateKey: dateKey, uid: user.uid);
    } else if (functions != null) {
      try {
        await functions.httpsCallable('markFirstReader').call({
          'dateKey': dateKey,
        });
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('markFirstReader failed: $e');
        }
        ErrorLogger.log(e, st);
      }
    }
  }
}

class _ReadLogPageState extends State<ReadLogPage> {
  final GlobalKey<ReadLogViewState> _viewKey = GlobalKey<ReadLogViewState>();

  void refresh() {
    _viewKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        context,
        "Today's Readers",
        automaticallyImplyLeading: false,
      ),
      body: ReadLogView(
        key: _viewKey,
        firestore: widget.firestore,
        auth: widget.auth,
        readingStatusService: widget.readingStatusService ??
            ReadingStatusService(
                firestore: widget.firestore, auth: widget.auth),
        onSendLikeNotification: widget.onSendLikeNotification,
        onSendCommentNotification: widget.onSendCommentNotification,
        dateProvider: widget.dateProvider,
        vibrationService: widget.vibrationService,
      ),
    );
  }
}

typedef ReadLogPageState = _ReadLogPageState;

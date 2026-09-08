import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
        automaticallyImplyLeading: true,
      ),
      body: ReadLogView(
        key: _viewKey,
        firestore: widget.firestore,
        auth: widget.auth,
        readingStatusService: widget.readingStatusService ??
            ReadingStatusService(
              firestore: widget.firestore,
              auth: widget.auth,
            ),
        onSendLikeNotification: widget.onSendLikeNotification,
        onSendCommentNotification: widget.onSendCommentNotification,
        dateProvider: widget.dateProvider,
        vibrationService: widget.vibrationService,
      ),
    );
  }
}

typedef ReadLogPageState = _ReadLogPageState;

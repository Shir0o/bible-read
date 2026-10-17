import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/sub_header.dart';
import '../widgets/views/streak_history_view.dart';

/// Displays the user's reading streak history.
class StreakHistoryPage extends StatelessWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  /// Creates a [StreakHistoryPage].
  StreakHistoryPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SubHeader(
              title: 'History',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: StreakHistoryView(firestore: firestore, auth: auth),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/journey/bible_library_grid.dart';
import '../widgets/journey/consistency_calendar.dart';
import '../widgets/journey/journey_header.dart';
import '../widgets/journey/journey_progress_card.dart';

class JourneyPage extends StatefulWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  const JourneyPage({
    super.key,
    required this.auth,
    required this.firestore,
  });

  @override
  State<JourneyPage> createState() => _JourneyPageState();
}

class _JourneyPageState extends State<JourneyPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            JourneyHeader(auth: widget.auth, firestore: widget.firestore),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    JourneyProgressCard(
                      firestore: widget.firestore,
                      auth: widget.auth,
                    ),
                    const SizedBox(height: 32),
                    BibleLibraryGrid(
                      firestore: widget.firestore,
                      auth: widget.auth,
                    ),
                    const SizedBox(height: 32),
                    ConsistencyCalendar(
                      firestore: widget.firestore,
                      auth: widget.auth,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

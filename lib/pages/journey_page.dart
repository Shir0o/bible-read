import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/journey/bible_library_grid.dart';
import '../widgets/journey/consistency_calendar.dart';
import '../widgets/journey/journey_progress_card.dart';
import '../services/vibration_service.dart';
import '../services/reading_plan_service.dart';
import '../services/bible_progress_service.dart';
import '../widgets/app_header.dart';
import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';

class JourneyPage extends StatefulWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final VibrationService vibrationService;
  final DateTime Function() dateProvider;

  const JourneyPage({
    super.key,
    required this.auth,
    required this.firestore,
    required this.vibrationService,
    required this.dateProvider,
  });

  @override
  State<JourneyPage> createState() => _JourneyPageState();
}

class _JourneyPageState extends State<JourneyPage>
    with AutomaticKeepAliveClientMixin {
  bool _isLoading = true;
  List<ReadingPlan>? _plans;
  List<UserPlanProgress>? _progress;
  Map<String, Set<int>>? _completedByBook;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = widget.auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    final readingPlanService =
        ReadingPlanService(firestore: widget.firestore);
    final bibleProgressService =
        BibleProgressService(firestore: widget.firestore);

    try {
      // Prepare futures for all critical components
      final results = await Future.wait([
        readingPlanService.getAvailablePlans(userId: user.uid),
        readingPlanService.getActivePlans(user.uid).first,
        bibleProgressService.completedChaptersByBook(user.uid),
      ]);

      if (mounted) {
        setState(() {
          _plans = results[0] as List<ReadingPlan>;
          _progress = results[1] as List<UserPlanProgress>;
          _completedByBook = results[2] as Map<String, Set<int>>;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error pre-loading Journey data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              auth: widget.auth,
              firestore: widget.firestore,
              vibrationService: widget.vibrationService,
              dateProvider: widget.dateProvider,
              customGreeting: 'Keep going,',
            ),
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
                      initialPlans: _plans,
                      initialProgress: _progress,
                      isLoading: _isLoading,
                    ),
                    const SizedBox(height: 32),
                    BibleLibraryGrid(
                      firestore: widget.firestore,
                      auth: widget.auth,
                      initialCompletedByBook: _completedByBook,
                      isLoading: _isLoading,
                    ),
                    const SizedBox(height: 32),
                    ConsistencyCalendar(
                      firestore: widget.firestore,
                      auth: widget.auth,
                      isLoading: _isLoading,
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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/data_cache_service.dart';

import '../widgets/journey/bible_library_grid.dart';
import '../widgets/journey/consistency_calendar.dart';
import '../widgets/journey/journey_progress_card.dart';
import '../services/vibration_service.dart';
import '../services/reading_plan_service.dart';
import '../services/bible_progress_service.dart';
import '../services/reading_status_service.dart';
import '../widgets/app_header.dart';
import '../models/reading_plan.dart';
import '../models/reading_plan_progress.dart';

class JourneyPage extends StatefulWidget {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final VibrationService vibrationService;
  final DateTime Function() dateProvider;

  /// Optional cache to avoid redundant data loading between tab switches.
  final DataCacheService? cache;

  const JourneyPage({
    super.key,
    required this.auth,
    required this.firestore,
    required this.vibrationService,
    required this.dateProvider,
    this.cache,
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
  Set<DateTime>? _readDates;

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

    final readingPlanService = ReadingPlanService(firestore: widget.firestore);
    final bibleProgressService = BibleProgressService(
      firestore: widget.firestore,
    );
    final readingStatusService = ReadingStatusService(
      firestore: widget.firestore,
      auth: widget.auth,
    );
    final cache = widget.cache;

    try {
      final now = widget.dateProvider();
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final cacheKey = 'journey:${user.uid}';

      // If cache has fresh data, use it directly.
      if (cache != null) {
        final cached = cache.peek<_JourneyData>(cacheKey);
        if (cached != null) {
          if (mounted) {
            setState(() {
              _plans = cached.plans;
              _progress = cached.progress;
              _completedByBook = cached.completedByBook;
              _readDates = cached.readDates;
              _isLoading = false;
            });
          }
          return;
        }
      }

      // Prepare futures for all critical components
      final results = await Future.wait([
        readingPlanService.getAvailablePlans(userId: user.uid),
        readingPlanService.getActivePlans(user.uid).first,
        bibleProgressService.completedChaptersByBook(user.uid),
        readingStatusService.getReadStatusForRange(
          user.uid,
          daysInMonth,
          referenceDate: now,
        ),
      ]);

      final plans = results[0] as List<ReadingPlan>;
      final progress = results[1] as List<UserPlanProgress>;
      final completedByBook = results[2] as Map<String, Set<int>>;
      final statusMap = results[3] as Map<String, bool>;
      final readDates = statusMap.entries
          .where((e) => e.value)
          .map((e) => DateTime.parse(e.key))
          .toSet();

      // Store in cache for next tab switch
      cache?.put<_JourneyData>(
        cacheKey,
        _JourneyData(
          plans: plans,
          progress: progress,
          completedByBook: completedByBook,
          readDates: readDates,
        ),
      );

      if (mounted) {
        setState(() {
          _plans = plans;
          _progress = progress;
          _completedByBook = completedByBook;
          _readDates = readDates;
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
              child: RefreshIndicator(
                onRefresh: _loadData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
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
                        vibrationService: widget.vibrationService,
                        dateProvider: widget.dateProvider,
                      ),
                      const SizedBox(height: 32),
                      BibleLibraryGrid(
                        firestore: widget.firestore,
                        auth: widget.auth,
                        initialCompletedByBook: _completedByBook,
                        isLoading: _isLoading,
                        vibrationService: widget.vibrationService,
                      ),
                      const SizedBox(height: 32),
                      ConsistencyCalendar(
                        firestore: widget.firestore,
                        auth: widget.auth,
                        initialReadDates: _readDates,
                        isLoading: _isLoading,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Value object holding pre-fetched data for the Journey tab.
/// Stored in [DataCacheService] to avoid re-fetching on tab switches.
class _JourneyData {
  final List<ReadingPlan> plans;
  final List<UserPlanProgress> progress;
  final Map<String, Set<int>> completedByBook;
  final Set<DateTime> readDates;

  const _JourneyData({
    required this.plans,
    required this.progress,
    required this.completedByBook,
    required this.readDates,
  });
}

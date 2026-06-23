import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/data_cache_service.dart';

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
  Set<DateTime>? _readDates;
  int _streak = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData();
    unawaited(_loadStreak());
  }

  /// Loads the current streak for the "Day streak" stat tile.
  Future<void> _loadStreak() async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    try {
      final doc = await widget.firestore
          .collection('users')
          .doc(user.uid)
          .collection('summary')
          .doc('data')
          .get();
      final streak = (doc.data()?['streak'] as num?)?.toInt() ?? 0;
      if (mounted) setState(() => _streak = streak);
    } catch (_) {
      // Best-effort; the tile simply shows 0 if unavailable.
    }
  }

  /// A single stat tile ("value unit" + label + sub), paired side-by-side on
  /// the Path screen (design: `path.jsx`).
  Widget _buildStatTile(
    BuildContext context, {
    required String value,
    required String unit,
    required String label,
    required String sub,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            Text(
              sub,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
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
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildStatTile(
                                context,
                                value: '${_readDates?.length ?? 0}',
                                unit: 'days',
                                label: 'Shown up',
                                sub: 'this month',
                              ),
                              const SizedBox(width: 12),
                              _buildStatTile(
                                context,
                                value: '$_streak',
                                unit: _streak == 1 ? 'day' : 'days',
                                label: 'Day streak',
                                sub: 'current',
                              ),
                            ],
                          ),
                        ),
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

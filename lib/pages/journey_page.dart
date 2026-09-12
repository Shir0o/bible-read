import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/group_service.dart';
import '../services/reading_plan_service.dart';
import '../services/user_preferences_service.dart';

import '../widgets/journey/badge_strip.dart';
import '../widgets/journey/consistency_calendar.dart';
import '../widgets/journey/plans_hub.dart';
import '../widgets/journey/read_through_card.dart';
import '../services/vibration_service.dart';
import '../services/reading_status_service.dart';
import '../widgets/app_header.dart';

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
  Set<DateTime>? _readDates;
  int _streak = 0;

  late final ReadingStatusService _statusService;
  StreamSubscription<Set<DateTime>>? _readDatesSub;
  StreamSubscription<int>? _streakSub;

  /// Reloads the plans hub; called together with the tab's own data refresh.
  final GlobalKey<PlansHubState> _hubKey = GlobalKey<PlansHubState>();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _statusService = ReadingStatusService(
      firestore: widget.firestore,
      auth: widget.auth,
      dateProvider: widget.dateProvider,
    );
    _subscribeReadDates();
    _subscribeStreak();
  }

  void _subscribeReadDates() {
    final user = widget.auth.currentUser;
    if (user == null) return;
    final now = widget.dateProvider();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    _readDatesSub?.cancel();
    _readDatesSub = _statusService
        .watchReadDatesForRange(user.uid, daysInMonth, referenceDate: now)
        .listen(
      (dates) {
        if (mounted) {
          setState(() {
            _readDates = dates;
            _isLoading = false;
          });
        }
      },
      onError: (Object e, StackTrace st) {
        debugPrint('Error watching Journey data: $e');
        if (mounted) setState(() => _isLoading = false);
      },
    );
  }

  void _subscribeStreak() {
    final user = widget.auth.currentUser;
    if (user == null) return;
    _streakSub?.cancel();
    _streakSub = _statusService.watchStreak(user.uid).listen(
      (streak) {
        if (mounted) setState(() => _streak = streak);
      },
      onError: (Object e, StackTrace st) =>
          debugPrint('Error watching streak: $e'),
    );
  }

  Future<void> _refresh() async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    final now = widget.dateProvider();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    try {
      final statusMap = await _statusService.getReadStatusForRange(
        user.uid,
        daysInMonth,
        referenceDate: now,
      );
      final readDates = statusMap.entries
          .where((e) => e.value)
          .map((e) => DateTime.parse(e.key))
          .toSet();
      if (mounted) {
        setState(() {
          _readDates = readDates;
          _isLoading = false;
        });
      }
      await _hubKey.currentState?.reload();
    } catch (e) {
      debugPrint('Error refreshing Journey data: $e');
    }
  }

  @override
  void dispose() {
    _readDatesSub?.cancel();
    _streakSub?.cancel();
    super.dispose();
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
              eyebrow: 'Keep going',
              title: 'Path',
              showNotificationBell: false,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      // The unified plan list — solo and shared in one place
                      // — is the tab itself now (#808).
                      PlansHub(
                        key: _hubKey,
                        firestore: widget.firestore,
                        auth: widget.auth,
                        groupService: GroupService(
                          firestore: widget.firestore,
                        ),
                        readingPlanService: ReadingPlanService(
                          firestore: widget.firestore,
                        ),
                        userPreferencesService: UserPreferencesService(
                          firestore: widget.firestore,
                        ),
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
                      // The Showing-up record sits beneath the plan list,
                      // and renders even for a reader with no plans (#808).
                      ConsistencyCalendar(
                        firestore: widget.firestore,
                        auth: widget.auth,
                        initialReadDates: _readDates,
                        isLoading: _isLoading,
                      ),
                      const SizedBox(height: 32),
                      ReadThroughCard(
                        firestore: widget.firestore,
                        auth: widget.auth,
                      ),
                      const SizedBox(height: 32),
                      BadgeStrip(
                        firestore: widget.firestore,
                        auth: widget.auth,
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

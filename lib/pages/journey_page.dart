import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/group_service.dart';
import '../services/reading_plan_service.dart';
import '../services/user_preferences_service.dart';

import '../theme/app_theme.dart';
import '../widgets/journey/consistency_card.dart';
import '../widgets/journey/plans_hub.dart';
import '../widgets/journey/read_through_card.dart';
import '../widgets/journey/seasonal_challenge_card.dart';
import '../services/vibration_service.dart';
import '../services/reading_status_service.dart';
import '../widgets/app_header.dart';
import 'create_plan_page.dart';

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
  bool _streakLoaded = false;
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
    if (user == null) {
      _isLoading = false;
      return;
    }
    final now = widget.dateProvider();
    // "This month" is the calendar month to date, counted from the same
    // source as the ConsistencyCalendar (reading docs plus Group feed
    // entries); the reading-doc stream only signals when to recount.
    final daysThisMonth = now.day;
    _readDatesSub?.cancel();
    _readDatesSub = _statusService
        .watchReadDatesForRange(user.uid, daysThisMonth, referenceDate: now)
        .asyncMap((_) => _readDatesThisMonth(user.uid, now))
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
    if (user == null) {
      _streakLoaded = true;
      return;
    }
    _streakSub?.cancel();
    _streakSub = _statusService.watchStreak(user.uid).listen(
      (streak) {
        if (mounted) {
          setState(() {
            _streak = streak;
            _streakLoaded = true;
          });
        }
      },
      onError: (Object e, StackTrace st) {
        debugPrint('Error watching streak: $e');
        if (mounted) setState(() => _streakLoaded = true);
      },
    );
  }

  /// Days shown up from the 1st of [now]'s month through [now].
  Future<Set<DateTime>> _readDatesThisMonth(String uid, DateTime now) async {
    final statusMap = await _statusService.getReadStatusForRange(
      uid,
      now.day,
      referenceDate: now,
    );
    return statusMap.entries
        .where((e) => e.value)
        .map((e) => DateTime.parse(e.key))
        .toSet();
  }

  Future<void> _refresh() async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    final now = widget.dateProvider();
    try {
      final readDates = await _readDatesThisMonth(user.uid, now);
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

  /// The header's "New plan" action: the same creation flow as the plan list's
  /// enroll button, reloading the list on return.
  Future<void> _openNewPlan() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreatePlanPage(
          firestore: widget.firestore,
          auth: widget.auth,
          vibrationService: widget.vibrationService,
          groupService: GroupService(firestore: widget.firestore),
        ),
      ),
    );
    if (mounted) await _hubKey.currentState?.reload();
  }

  @override
  void dispose() {
    _readDatesSub?.cancel();
    _streakSub?.cancel();
    super.dispose();
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.hPadding,
        0,
        AppSpacing.hPadding,
        AppSpacing.gap12,
      ),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
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
              action: AppHeaderAction(
                label: 'New plan',
                onPressed: _openNewPlan,
              ),
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
                      const SizedBox(height: AppSpacing.gap8),
                      // The unified plan list — solo and shared in one place
                      // — is the tab itself now (#808).
                      Column(
                        key: const Key('path-plans'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionTitle(context, 'Plans'),
                          PathChallengeCard(
                            firestore: widget.firestore,
                            auth: widget.auth,
                            vibrationService: widget.vibrationService,
                            dateProvider: widget.dateProvider,
                          ),
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
                        ],
                      ),
                      const SizedBox(height: AppSpacing.gap32),
                      // The Showing-up record sits beneath the plan list,
                      // and renders even for a reader with no plans (#808).
                      Column(
                        key: const Key('path-consistency'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionTitle(context, 'Consistency'),
                          ConsistencyCard(
                            firestore: widget.firestore,
                            auth: widget.auth,
                            loading: _isLoading || !_streakLoaded,
                            streak: _streak,
                            readDates: _readDates,
                            now: widget.dateProvider(),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.gap32),
                      Column(
                        key: const Key('path-read-throughs'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionTitle(context, 'Read-throughs'),
                          ReadThroughCard(
                            firestore: widget.firestore,
                            auth: widget.auth,
                          ),
                        ],
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

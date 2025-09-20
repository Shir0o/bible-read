import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/error_logger.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/achievement.dart';
import '../models/season.dart';
import '../models/seasonal_challenge.dart';
import '../models/seasonal_challenge_progress.dart';
import '../services/achievement_service.dart';
import '../services/notification_service.dart';
import '../services/reading_status_service.dart';
import '../services/seasonal_challenge_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_styles.dart';
import '../widgets/menu_button.dart';
import '../widgets/notification_button.dart';
import '../widgets/read_status_section.dart';
import '../widgets/success_animation.dart';
import 'read_log_page.dart';
import 'seasonal_challenges_page.dart';

/// Landing page that displays reading progress and loads user data from
/// Firestore when the app starts.
class HomePage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  /// Cloud Functions instance used for first reader checks.
  final FirebaseFunctions? functions;

  /// Optional handler to mark the first reader for testing.
  final Future<Map<String, dynamic>?> Function({
    required String dateKey,
    required String uid,
  })? markFirstReader;

  static final SeasonalChallengeService _defaultSeasonalChallengeService =
      SeasonalChallengeService();

  HomePage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    this.functions,
    this.markFirstReader,
    ReadingStatusService? readingStatusService,
    SeasonalChallengeService? seasonalChallengeService,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance,
        readingStatusService = readingStatusService ??
            ReadingStatusService(firestore: firestore, auth: auth),
        seasonalChallengeService =
            seasonalChallengeService ?? _defaultSeasonalChallengeService;

  /// Service for loading and updating reading status.
  final ReadingStatusService readingStatusService;

  /// Service for seasonal challenge progress and metadata.
  final SeasonalChallengeService seasonalChallengeService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  bool _disposed = false;
  bool _readToday = false;

  /// Whether the page is currently fetching or toggling the read status.
  bool _toggleLoading = false;
  List<bool> _pastWeek = [];
  List<bool> _pastMonth = [];
  Set<DateTime> _readDates = {};
  bool _seasonLoading = false;
  Season? _activeSeason;
  List<SeasonalChallenge> _seasonChallenges = const [];
  final Map<String, SeasonalChallengeProgress?> _progressByChallenge = {};
  StreamSubscription<List<SeasonalChallenge>>? _challengeSubscription;
  final Map<String, StreamSubscription<SeasonalChallengeProgress?>>
      _progressSubscriptions = {};

  @override
  void initState() {
    super.initState();
    _loadReadStatus();
    unawaited(_initializeSeasonalChallenges());
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seasonalChallengeService != widget.seasonalChallengeService ||
        oldWidget.auth != widget.auth) {
      unawaited(_initializeSeasonalChallenges());
    }
  }

  /// Fetches today's read flag and calendar history.
  Future<void> _loadReadStatus({bool showLoading = true}) async {
    if (showLoading && !_disposed && mounted) {
      setState(() {
        _toggleLoading = true; // Start loading indicator.
      });
    }

    try {
      final status = await widget.readingStatusService.fetchStatus();
      if (!_disposed && mounted) {
        setState(() {
          _readToday = status.readToday;
          _pastWeek = status.pastWeek;
          _pastMonth = status.pastMonth;
          _readDates = status.readDates;
        });
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Error loading status: $e');
      }
      ErrorLogger.log(e, st);
    } finally {
      if (showLoading && !_disposed && mounted) {
        setState(() {
          _toggleLoading = false; // Always stop loading.
        });
      }
    }
  }

  Future<void> _initializeSeasonalChallenges() async {
    if (!_disposed && mounted) {
      setState(() {
        _seasonLoading = true;
      });
    } else {
      _seasonLoading = true;
    }

    try {
      final season = await widget.seasonalChallengeService.fetchActiveSeason();
      if (!_disposed && mounted) {
        setState(() {
          _activeSeason = season;
        });
      } else {
        _activeSeason = season;
      }
      await _subscribeToChallenges(season);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to load seasonal challenges: $e');
      }
      await ErrorLogger.log(e, st);
      await _cancelSeasonalSubscriptions();
      if (!_disposed && mounted) {
        setState(() {
          _activeSeason = null;
          _seasonChallenges = const [];
          _progressByChallenge.clear();
        });
      } else {
        _activeSeason = null;
        _seasonChallenges = const [];
        _progressByChallenge.clear();
      }
    } finally {
      if (!_disposed && mounted) {
        setState(() {
          _seasonLoading = false;
        });
      } else {
        _seasonLoading = false;
      }
    }
  }

  Future<void> _subscribeToChallenges(Season? season) async {
    final previous = _challengeSubscription;
    _challengeSubscription = null;
    if (previous != null) {
      await previous.cancel();
    }
    await _cancelProgressSubscriptions();

    if (season == null) {
      if (!_disposed && mounted) {
        setState(() {
          _seasonChallenges = const [];
          _progressByChallenge.clear();
        });
      } else {
        _seasonChallenges = const [];
        _progressByChallenge.clear();
      }
      return;
    }

    _challengeSubscription = widget.seasonalChallengeService
        .streamChallenges(season.id)
        .listen((challenges) {
      if (!_disposed && mounted) {
        setState(() {
          _seasonChallenges = challenges;
        });
      } else {
        _seasonChallenges = challenges;
      }
      unawaited(_updateProgressSubscriptions(season.id, challenges));
    }, onError: (Object error, StackTrace stackTrace) {
      if (kDebugMode) {
        debugPrint('Seasonal challenge stream error: $error');
      }
      unawaited(ErrorLogger.log(error, stackTrace));
    });
  }

  Future<void> _updateProgressSubscriptions(
    String seasonId,
    List<SeasonalChallenge> challenges,
  ) async {
    final userId = widget.auth.currentUser?.uid;
    if (userId == null) {
      await _cancelProgressSubscriptions();
      if (!_disposed && mounted) {
        setState(() {
          _progressByChallenge.clear();
        });
      } else {
        _progressByChallenge.clear();
      }
      return;
    }

    final activeChallengeIds = challenges.map((c) => c.id).toSet();
    final toRemove = _progressSubscriptions.keys
        .where((id) => !activeChallengeIds.contains(id))
        .toList();
    for (final id in toRemove) {
      final subscription = _progressSubscriptions.remove(id);
      if (subscription != null) {
        await subscription.cancel();
      }
      _progressByChallenge.remove(id);
    }

    for (final challenge in challenges) {
      if (_progressSubscriptions.containsKey(challenge.id)) {
        continue;
      }
      final subscription = widget.seasonalChallengeService
          .streamProgress(
        uid: userId,
        seasonId: seasonId,
        challengeId: challenge.id,
      )
          .listen((progress) {
        if (!_disposed && mounted) {
          setState(() {
            _progressByChallenge[challenge.id] = progress;
          });
        } else {
          _progressByChallenge[challenge.id] = progress;
        }
      }, onError: (Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          debugPrint('Seasonal progress stream error: $error');
        }
        unawaited(ErrorLogger.log(error, stackTrace));
      });
      _progressSubscriptions[challenge.id] = subscription;
    }

    if (!_disposed && mounted) {
      setState(() {});
    }
  }

  Future<void> _cancelSeasonalSubscriptions() async {
    final challengeSubscription = _challengeSubscription;
    _challengeSubscription = null;
    if (challengeSubscription != null) {
      await challengeSubscription.cancel();
    }
    await _cancelProgressSubscriptions();
  }

  Future<void> _cancelProgressSubscriptions() async {
    if (_progressSubscriptions.isEmpty) {
      return;
    }
    final subscriptions =
        List<StreamSubscription<SeasonalChallengeProgress?>>.from(
      _progressSubscriptions.values,
    );
    _progressSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  /// Cleans and updates the cached summary document without scanning the entire
  /// reading collection. Removes outdated entries, ensures the summary document
  /// exists and resets the streak if a day was missed.
  Future<void> _updateSummary() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    try {
      final stats = await widget.readingStatusService.updateSummary();
      await _checkAchievements(user.uid, stats.streak, stats.totalReadDays);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to update summary: $e');
      }
      ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update summary. Please try again.'),
          ),
        );
        unawaited(_loadReadStatus(showLoading: false));
      }
    }
  }

  /// Marks the current day as read. Optimistically updates local state and
  /// writes the change to Firestore, rolling back on failure.
  Future<void> _toggleReadStatus() async {
    if (_readToday) return;

    final user = widget.auth.currentUser;
    if (user == null) return;

    // Reload user before writing to Firestore.
    await user.reload();
    final refreshedUser = widget.auth.currentUser;

    // Preserve current state in case we need to revert on error.
    final prevWeek = List<bool>.from(_pastWeek);
    final prevMonth = List<bool>.from(_pastMonth);
    final prevReadDates = Set<DateTime>.from(_readDates);

    final today = DateTime.now();
    final weekIndex = today.weekday % 7;
    final monthIndex = today.day - 1;
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;

    if (!_disposed && mounted) {
      setState(() {
        // Optimistically mark today as read in local state.
        _readToday = true;
        if (_pastWeek.length < 7) {
          _pastWeek = List<bool>.generate(
            7,
            (i) => i < _pastWeek.length ? _pastWeek[i] : false,
          );
        }
        _pastWeek[weekIndex] = true;
        if (_pastMonth.length < daysInMonth) {
          _pastMonth = List<bool>.generate(
            daysInMonth,
            (i) => i < _pastMonth.length ? _pastMonth[i] : false,
          );
        }
        _pastMonth[monthIndex] = true;
        _readDates.add(DateTime(today.year, today.month, today.day));
      });
    }

    try {
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      await ReadLogPage.writeReadLogEntry(
        refreshedUser ?? user,
        firestore: widget.firestore,
        functions: widget.functions,
        markFirstReader: widget.markFirstReader,
        dateProvider: () => today,
      );

      await widget.firestore
          .collection('users')
          .doc(user.uid)
          .collection('reading')
          .doc(dateKey)
          .set({
        'read': true,
      }, SetOptions(merge: true)); // Mark read in Firestore.

      // Update summary collection (lightweight update)
      await _updateSummaryWithToday();

      unawaited(_incrementSeasonalProgress());

      if (!_disposed && mounted) {
        SuccessAnimation.show(context);
      }

      unawaited(_loadReadStatus(showLoading: false));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to mark reading: $e');
      }
      ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        // Revert to previous state and notify the user.
        setState(() {
          _readToday = false;
          _pastWeek = prevWeek;
          _pastMonth = prevMonth;
          _readDates = prevReadDates;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to mark reading. Please try again.'),
          ),
        );
      }
    }
  }

  /// Lightweight summary update for today's read. Updates streak and cached
  /// read-date arrays without recomputing historical data.
  Future<void> _updateSummaryWithToday() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    try {
      final userDocRef = widget.firestore.collection('users').doc(user.uid);
      final summaryDocRef = userDocRef.collection('summary').doc('data');
      // Load existing summary values to increment cached fields.
      final doc = await summaryDocRef.get();
      final data = doc.data() ?? {};

      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      final yesterdayDateKey =
          '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

      final yesterdayDoc =
          await userDocRef.collection('reading').doc(yesterdayDateKey).get();

      int streak = (data['streak'] is int) ? data['streak'] : 0;
      if (yesterdayDoc.exists && yesterdayDoc.data()?['read'] == true) {
        streak += 1;
      } else {
        streak = 1; // Reset streak if yesterday was missed
      }

      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      var pastWeekReadDates = List<String>.from(
        data['pastWeekReadDates'] ?? [],
      );
      pastWeekReadDates = pastWeekReadDates
          .where((d) {
            final parsed = DateTime.tryParse(d);
            if (parsed == null) return false;
            final diff = today.difference(parsed).inDays;
            return diff >= 0 && diff < 7;
          })
          .toSet()
          .toList();
      pastWeekReadDates.add(dateKey);
      pastWeekReadDates = pastWeekReadDates.toSet().toList();
      if (pastWeekReadDates.length > 7) {
        pastWeekReadDates =
            pastWeekReadDates.sublist(pastWeekReadDates.length - 7);
      }

      var pastMonthReadDates = List<String>.from(
        data['pastMonthReadDates'] ?? [],
      );
      pastMonthReadDates = pastMonthReadDates
          .where((d) {
            final parsed = DateTime.tryParse(d);
            if (parsed == null) return false;
            final diff = today.difference(parsed).inDays;
            return diff >= 0 && diff < 30;
          })
          .toSet()
          .toList();
      pastMonthReadDates.add(dateKey);
      pastMonthReadDates = pastMonthReadDates.toSet().toList();
      if (pastMonthReadDates.length > 30) {
        pastMonthReadDates =
            pastMonthReadDates.sublist(pastMonthReadDates.length - 30);
      }

      int totalReadDays =
          (data['totalReadDays'] is int) ? data['totalReadDays'] : 0;
      totalReadDays += 1;

      int longestStreak =
          (data['longestStreak'] is int) ? data['longestStreak'] : streak;
      if (streak > longestStreak) {
        longestStreak = streak;
      }

      await summaryDocRef.set({
        'streak': streak,
        'pastWeekReadDates': pastWeekReadDates,
        'pastMonthReadDates': pastMonthReadDates,
        'totalReadDays': totalReadDays,
        'longestStreak': longestStreak,
      }, SetOptions(merge: true)); // Persist updated summary.

      await _checkAchievements(user.uid, streak, totalReadDays);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to update summary with today: \$e');
      }
      ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update summary. Please try again.'),
          ),
        );
        unawaited(_loadReadStatus(showLoading: false));
      }
    }
  }

  Future<void> _incrementSeasonalProgress() async {
    final user = widget.auth.currentUser;
    final season = _activeSeason;
    if (user == null || season == null) {
      return;
    }

    if (_seasonChallenges.isEmpty) {
      return;
    }

    for (final challenge in _seasonChallenges) {
      final progress = _progressByChallenge[challenge.id];
      if (!challenge.repeatable && _isChallengeComplete(challenge, progress)) {
        continue;
      }

      try {
        final updated = await widget.seasonalChallengeService
            .incrementDailyProgress(uid: user.uid, challenge: challenge);
        if (!_disposed && mounted) {
          setState(() {
            _progressByChallenge[challenge.id] = updated;
          });
        } else {
          _progressByChallenge[challenge.id] = updated;
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('Failed to increment seasonal challenge: $e');
        }
        await ErrorLogger.log(e, st);
      }
    }
  }

  /// Unlocks achievements based on the user's streak and total read days.
  Future<void> _checkAchievements(
    String uid,
    int streak,
    int totalReadDays,
  ) async {
    try {
      final service = AchievementService(firestore: widget.firestore);
      if (streak >= 7) {
        await service.unlockAchievement(
          uid,
          Achievement(
            id: 'streak7',
            title: '7-Day Streak',
            type: 'streak',
            dateUnlocked: DateTime.now(),
          ),
        );
      }
      if (totalReadDays >= 30) {
        await service.unlockAchievement(
          uid,
          Achievement(
            id: 'days30',
            title: '30 Days Read',
            type: 'days',
            dateUnlocked: DateTime.now(),
          ),
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to unlock achievements: $e');
      }
      ErrorLogger.log(e, st);
    }
  }

  SeasonalChallenge? _selectFeaturedChallenge() {
    if (_seasonChallenges.isEmpty) {
      return null;
    }
    for (final challenge in _seasonChallenges) {
      if (!_isChallengeComplete(challenge)) {
        return challenge;
      }
    }
    return _seasonChallenges.first;
  }

  bool _allChallengesCompleted() {
    if (_seasonChallenges.isEmpty) {
      return false;
    }
    for (final challenge in _seasonChallenges) {
      if (!_isChallengeComplete(challenge)) {
        return false;
      }
    }
    return true;
  }

  bool _isChallengeComplete(
    SeasonalChallenge challenge, [
    SeasonalChallengeProgress? progress,
  ]) {
    final resolved = progress ?? _progressByChallenge[challenge.id];
    if (resolved == null) {
      return false;
    }
    if (resolved.completedAt != null) {
      return true;
    }
    if (challenge.goal <= 0) {
      return false;
    }
    return resolved.totalProgress >= challenge.goal;
  }

  Widget _buildSeasonalSummary() {
    final theme = Theme.of(context);
    final season = _activeSeason;
    final titleStyle =
        theme.textTheme.titleMedium?.merge(AppTextStyles.subtitle) ??
            AppTextStyles.subtitle;
    final bodyStyle = theme.textTheme.bodyMedium?.merge(AppTextStyles.body) ??
        AppTextStyles.body;
    final subtleStyle = theme.textTheme.bodySmall?.merge(AppTextStyles.body) ??
        AppTextStyles.body;

    Widget buildCard(List<Widget> children) {
      return CommonStyles.buildCard(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
    }

    if (_seasonLoading) {
      return buildCard([
        Text('Seasonal challenges', style: titleStyle),
        const SizedBox(height: 12),
        Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Loading latest seasonal challenges...',
                style: bodyStyle,
              ),
            ),
          ],
        ),
      ]);
    }

    if (season == null) {
      return buildCard([
        Text('Seasonal challenges', style: titleStyle),
        const SizedBox(height: 8),
        Text(
          'No active seasonal challenge is available right now. Check back soon!',
          style: bodyStyle,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _openSeasonalChallengesPage,
            child: const Text('View challenges'),
          ),
        ),
      ]);
    }

    if (_seasonChallenges.isEmpty) {
      return buildCard([
        Text(
          season.title.isEmpty ? 'Seasonal challenges' : season.title,
          style: titleStyle,
        ),
        const SizedBox(height: 8),
        Text(
          'New challenges will arrive shortly.',
          style: bodyStyle,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _openSeasonalChallengesPage,
            child: const Text('View season'),
          ),
        ),
      ]);
    }

    if (_allChallengesCompleted()) {
      return buildCard([
        Text(
          season.title.isEmpty ? 'Seasonal challenges' : season.title,
          style: titleStyle,
        ),
        const SizedBox(height: 8),
        Text(
          'You have completed every challenge this season. Celebrate your progress!',
          style: bodyStyle,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _openSeasonalChallengesPage,
            child: const Text('View rewards'),
          ),
        ),
      ]);
    }

    final featured = _selectFeaturedChallenge();
    if (featured == null) {
      return buildCard([
        Text(
          season.title.isEmpty ? 'Seasonal challenges' : season.title,
          style: titleStyle,
        ),
        const SizedBox(height: 8),
        Text(
          "Explore this season's challenges.",
          style: bodyStyle,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _openSeasonalChallengesPage,
            child: const Text('View challenges'),
          ),
        ),
      ]);
    }

    final progress = _progressByChallenge[featured.id];
    final total = progress?.totalProgress ?? 0;
    final goal = featured.goal <= 0 ? 0 : featured.goal;
    final materialLocalizations = MaterialLocalizations.of(context);
    final completion = goal <= 0
        ? (progress == null ? 0.0 : 1.0)
        : (total / goal).clamp(0.0, 1.0);
    final progressLabel = goal <= 0
        ? '${materialLocalizations.formatDecimal(total)} ${featured.metric}'
            .trim()
        : '${materialLocalizations.formatDecimal(math.min(total, goal))} / '
                '${materialLocalizations.formatDecimal(goal)} ${featured.metric}'
            .trim();
    final isComplete = _isChallengeComplete(featured, progress);
    final isClaimed = progress?.rewardClaimedAt != null;
    String message;
    if (isClaimed) {
      message = 'Reward claimed! Explore the details on the seasonal page.';
    } else if (isComplete) {
      message = 'You have completed this challenge. Claim your reward!';
    } else if (featured.description.isNotEmpty) {
      message = featured.description;
    } else {
      message = 'Keep going to finish this challenge.';
    }

    final buttonLabel =
        isComplete && !isClaimed ? 'Claim reward' : 'View challenges';

    return buildCard([
      Text(
        season.title.isEmpty ? 'Seasonal challenges' : season.title,
        style: titleStyle,
      ),
      const SizedBox(height: 4),
      Text(
        featured.title,
        style: bodyStyle.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      LinearProgressIndicator(
        value: goal <= 0 ? null : completion,
        minHeight: 6,
      ),
      const SizedBox(height: 8),
      Text(progressLabel, style: subtleStyle),
      const SizedBox(height: 8),
      Text(message, style: subtleStyle),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _openSeasonalChallengesPage,
          child: Text(buttonLabel),
        ),
      ),
    ]);
  }

  Future<void> _openSeasonalChallengesPage() async {
    if (!mounted) {
      return;
    }
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => SeasonalChallengesPage(
            service: widget.seasonalChallengeService,
          ),
        ),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to open seasonal challenges: $e');
      }
      await ErrorLogger.log(e, st);
    }
  }

  /// Adds a like entry for today's reading document.
  Future<void> likeReading() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final userDocRef = widget.firestore.collection('users').doc(user.uid);

    try {
      await userDocRef
          .collection('reading')
          .doc(dateKey)
          .collection('likes')
          .doc(user.uid)
          .set({'timestamp': Timestamp.now()}); // Record like with timestamp.
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to like reading: $e');
      }
      ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to like reading. Please try again.'),
          ),
        );
      }
    }
  }

  /// Removes the current user's like from today's reading document.
  Future<void> unlikeReading() async {
    final user = widget.auth.currentUser;
    if (user == null) return;

    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final userDocRef = widget.firestore.collection('users').doc(user.uid);

    try {
      await userDocRef
          .collection('reading')
          .doc(dateKey)
          .collection('likes')
          .doc(user.uid)
          .delete();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to unlike reading: $e');
      }
      ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to unlike reading. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Bible Reading Challenge',
          style: CommonStyles.appBarTitleText,
        ),
        backgroundColor: AppTheme.backgroundColor,
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: _buildMainContent(),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    if (widget.auth.currentUser == null) {
      return Center(
        child: Text(
          'User not signed in.',
          style: AppTextStyles.subtitle.copyWith(color: Colors.white70),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        try {
          await widget.auth.currentUser?.reload();
          final googleAccount = await GoogleSignIn().signInSilently();
          final firebaseUser = widget.auth.currentUser;
          if (googleAccount != null && firebaseUser != null) {
            await firebaseUser.updateDisplayName(googleAccount.displayName);
            await firebaseUser.reload();
          }
          await _updateSummary();
          await _initializeSeasonalChallenges();
          await _loadReadStatus();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Refreshed successfully')),
          );
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('Refresh failed: \$e');
          }
          ErrorLogger.log(e, st);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to refresh data. Please try again.'),
            ),
          );
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.only(
            top: 16.0,
            bottom: 48,
            left: 16,
            right: 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSeasonalSummary(),
              const SizedBox(height: 24),
              ReadStatusSection(
                toggleLoading: _toggleLoading,
                readToday: _readToday,
                onToggle: _toggleReadStatus,
                readDates: _readDates,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    final challengeSubscription = _challengeSubscription;
    _challengeSubscription = null;
    if (challengeSubscription != null) {
      unawaited(challengeSubscription.cancel());
    }
    if (_progressSubscriptions.isNotEmpty) {
      for (final subscription in _progressSubscriptions.values) {
        unawaited(subscription.cancel());
      }
      _progressSubscriptions.clear();
    }
    _progressByChallenge.clear();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;
}

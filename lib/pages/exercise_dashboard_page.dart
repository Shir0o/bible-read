import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/exercise_challenge.dart';
import '../services/error_logger.dart';
import '../services/exercise_tracker_service.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_styles.dart';
import '../widgets/exercise_status_section.dart';
import 'exercise_challenges_page.dart';

/// Dedicated page for viewing and logging daily exercise challenges.
class ExerciseDashboardPage extends StatefulWidget {
  ExerciseDashboardPage({
    super.key,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    ExerciseTrackerService? trackerService,
    VibrationService? vibrationService,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance,
        trackerService = trackerService ??
            ExerciseTrackerService(firestore: firestore, auth: auth),
        vibrationService = vibrationService ?? const VibrationService();

  /// Firestore instance shared with the tracker service.
  final FirebaseFirestore firestore;

  /// Authentication instance for resolving the current user.
  final FirebaseAuth auth;

  /// Service responsible for reading and writing exercise data.
  final ExerciseTrackerService trackerService;

  /// Vibration service for UI feedback when logging progress.
  final VibrationService vibrationService;

  @override
  State<ExerciseDashboardPage> createState() => _ExerciseDashboardPageState();
}

class _ExerciseDashboardPageState extends State<ExerciseDashboardPage>
    with AutomaticKeepAliveClientMixin {
  bool _disposed = false;
  bool _loading = true;
  List<ExerciseChallengeSummary> _summaries = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSummaries());
  }

  @override
  void didUpdateWidget(covariant ExerciseDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth ||
        oldWidget.trackerService != widget.trackerService) {
      unawaited(_loadSummaries());
    }
  }

  Future<bool> _loadSummaries({bool setLoading = true}) async {
    final user = widget.auth.currentUser;
    if (user == null) {
      if (!_disposed && mounted) {
        setState(() {
          _summaries = const [];
          _error = null;
          _loading = false;
        });
      }
      return true;
    }

    if (!_disposed && mounted) {
      setState(() {
        if (setLoading) {
          _loading = true;
        }
        _error = null;
      });
    }

    var success = false;

    try {
      final summaries =
          await widget.trackerService.fetchChallengeSummaries(uid: user.uid);
      if (!_disposed && mounted) {
        setState(() {
          _summaries = summaries;
          _error = null;
        });
      }
      success = true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to load exercise summaries: $e');
      }
      await ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        setState(() {
          _error = 'Failed to load exercise progress. Please try again.';
        });
      }
    } finally {
      if (!_disposed && mounted) {
        setState(() {
          _loading = false;
        });
      }
    }

    return success;
  }

  Future<void> _recordAmount(
    ExerciseChallenge challenge,
    double amount, {
    bool replace = false,
  }) async {
    if (amount.isNaN || amount.isInfinite) {
      return;
    }
    try {
      await widget.trackerService.recordDailyAmount(
        challenge: challenge,
        amount: amount,
        replace: replace,
      );
      await _loadSummaries(setLoading: false);
      if (_disposed || !mounted) {
        return;
      }
      unawaited(widget.vibrationService.mediumImpact());
      final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
      final label = _formatAmount(amount, challenge.unit);
      final message = replace
          ? 'Logged $label for ${challenge.name}.'
          : 'Added $label to ${challenge.name}.';
      messenger.showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to record exercise amount: $e');
      }
      await ErrorLogger.log(e, st);
      if (_disposed || !mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content:
                Text('Failed to record exercise progress. Please try again.'),
          ),
        );
    }
  }

  Future<void> _openExerciseChallenges() async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ExerciseChallengesPage(
          trackerService: widget.trackerService,
          vibrationService: widget.vibrationService,
        ),
      ),
    );
    if (_disposed || !mounted) {
      return;
    }
    await _loadSummaries();
  }

  void _retrySummaries() {
    unawaited(_loadSummaries());
  }

  String _formatAmount(double value, String unit) {
    final fixed = value.toStringAsFixed(2);
    final trimmed = fixed
        .replaceFirst(RegExp(r'\.0+\$'), '')
        .replaceFirst(RegExp(r'(\.\d*?[1-9])0+\$'), r'\1');
    final amount = trimmed.isEmpty ? '0' : trimmed;
    if (unit.isEmpty) {
      return amount;
    }
    return '$amount $unit';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Daily Exercise',
          style: CommonStyles.appBarTitleText,
        ),
        backgroundColor: AppTheme.backgroundColor,
      ),
      body: Container(
        decoration: CommonStyles.backgroundGradient,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: _buildContent(),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent() {
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
        final success = await _loadSummaries();
        if (!mounted) {
          return;
        }
        final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Refreshed exercise data successfully.'
                  : 'Exercise data may be out of date.',
            ),
          ),
        );
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
          child: ExerciseStatusSection(
            loading: _loading,
            summaries: _summaries,
            error: _error,
            onRecordAmount: _recordAmount,
            onOpenChallenges: _openExerciseChallenges,
            onCreateChallenge: _openExerciseChallenges,
            onRetry: _retrySummaries,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;
}

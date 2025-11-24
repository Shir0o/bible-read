import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// A custom refresh indicator that pushes content down and displays a thick
/// progress bar with success/error states.
class ElegantRefreshIndicator extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Color? color;
  final Color? backgroundColor;

  const ElegantRefreshIndicator({
    super.key,
    required this.onRefresh,
    this.color,
    this.backgroundColor,
    this.refreshTriggerPullDistance = 115.0,
    this.refreshIndicatorExtent = 60.0,
  });

  final double refreshTriggerPullDistance;
  final double refreshIndicatorExtent;

  @override
  State<ElegantRefreshIndicator> createState() =>
      _ElegantRefreshIndicatorState();
}

enum _RefreshResult { none, success, error }

class _ElegantRefreshIndicatorState extends State<ElegantRefreshIndicator>
    with SingleTickerProviderStateMixin {
  final GlobalKey _refreshKey = GlobalKey();
  _RefreshResult _result = _RefreshResult.none;
  late AnimationController _progressController;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _progressController.dispose();
    _delayTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    _result = _RefreshResult.none;
    
    _progressController.reset();
    
    // Wait for the bounce-back animation to complete (approx 400ms)
    // before starting the progress bar animation
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        // Animate to 95% over 10 seconds while waiting for the refresh
        _progressController.animateTo(0.95, duration: const Duration(seconds: 10), curve: Curves.linear);
      }
    });

    try {
      // Minimum duration to ensure the loading animation is seen
      final minWait = Future.delayed(const Duration(seconds: 1));
      // Add a safety timeout to the user's refresh task
      final refreshTask = widget.onRefresh().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Refresh timed out');
        },
      );
      
      await Future.wait([minWait, refreshTask]);
      
      // Complete the progress bar
      await _progressController.animateTo(1.0, duration: const Duration(milliseconds: 200));
      
      if (mounted) {
        setState(() {
          _result = _RefreshResult.success;
        });
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = _RefreshResult.error;
        });
        HapticFeedback.mediumImpact();
      }
    }

    // Show the result state for a moment before collapsing
    if (mounted) {
      final completer = Completer<void>();
      _delayTimer = Timer(const Duration(milliseconds: 800), () {
        completer.complete();
      });
      try {
        await completer.future;
      } catch (e) {
        // Ignore errors if completer is completed with error or cancelled
      }
    }
    
    if (mounted) {
      setState(() {
        _result = _RefreshResult.none;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.color ?? AppTheme.colorScheme.primary;
    
    return CupertinoSliverRefreshControl(
      key: _refreshKey,
      onRefresh: _handleRefresh,
      refreshTriggerPullDistance: widget.refreshTriggerPullDistance,
      refreshIndicatorExtent: widget.refreshIndicatorExtent,
      builder: (
        BuildContext context,
        RefreshIndicatorMode refreshState,
        double pulledExtent,
        double refreshTriggerPullDistance,
        double refreshIndicatorExtent,
      ) {
        final double percentage = ((pulledExtent - refreshIndicatorExtent) /
                (refreshTriggerPullDistance - refreshIndicatorExtent))
            .clamp(0.0, 1.0);

        return Container(
          color: widget.backgroundColor ?? Colors.transparent,
          height: pulledExtent, // Occupy the full pulled space
          child: _buildContent(
            refreshState,
            percentage,
            primaryColor,
            pulledExtent,
            pulledExtent,
          ),
        );
      },
    );
  }

  Widget _buildContent(
    RefreshIndicatorMode refreshState,
    double percentage,
    Color primaryColor,
    double height,
    double pulledExtent,
  ) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _buildContentBody(refreshState, percentage, primaryColor, height, pulledExtent),
    );
  }

  Widget _buildContentBody(
    RefreshIndicatorMode refreshState,
    double percentage,
    Color primaryColor,
    double height,
    double pulledExtent,
  ) {
    // 1. Result State (Success/Error) - takes precedence
    if (_result == _RefreshResult.success) {
      return _buildResultBar(
        key: const ValueKey('success'),
        color: Colors.green,
        icon: Icons.check,
        label: 'Refreshed',
        height: height,
      );
    } else if (_result == _RefreshResult.error) {
      return _buildResultBar(
        key: const ValueKey('error'),
        color: Colors.redAccent,
        icon: Icons.error_outline,
        label: 'Failed',
        height: height,
      );
    }

    // 2. Refreshing State
    // Only switch to loading bar once we've bounced back to the resting height
    if (refreshState == RefreshIndicatorMode.refresh &&
        pulledExtent <= widget.refreshIndicatorExtent + 1.0) {
      return _buildLoadingBar(primaryColor, height, key: const ValueKey('loading'));
    }

    // 3. Pulling State (or bouncing back)
    return _buildPullingBar(percentage, primaryColor, height, key: const ValueKey('pulling'));
  }

  Widget _buildPullingBar(double percentage, Color color, double height, {Key? key}) {
    return Container(
      key: key,
      height: height,
      width: double.infinity,
      color: color.withOpacity(0.2),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: percentage,
        heightFactor: 1.0,
        child: Container(
          color: color,
        ),
      ),
    );
  }

  Widget _buildLoadingBar(Color color, double height, {Key? key}) {
    return AnimatedBuilder(
      key: key,
      animation: _progressController,
      builder: (context, child) {
        return Container(
          height: height,
          width: double.infinity,
          color: color.withOpacity(0.2),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: _progressController.value,
            heightFactor: 1.0,
            child: Container(
              color: color,
            ),
          ),
        );
      },
    );
  }

  Widget _buildResultBar({
    required Color color,
    required IconData icon,
    required String label,
    required double height,
    Key? key,
  }) {
    return Container(
      key: key,
      height: height,
      width: double.infinity,
      color: color,
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

/// A wrapper that switches between a [skeleton] and a [child] based on
/// [loading] state, while enforcing a [minTime] for the skeleton to be visible.
///
/// This prevents the UI from flashing if the content loads very quickly.
class SkeletonLoader extends StatefulWidget {
  /// Whether the content is currently loading.
  final bool loading;

  /// The widget to display when loading is complete.
  final Widget child;

  /// The skeleton widget to display while loading.
  final Widget skeleton;

  /// The minimum time the skeleton should be visible.
  /// Defaults to 500ms.
  final Duration minTime;

  /// Curve for the fade transition between skeleton and content.
  final Curve switchCurve;

  /// Duration for the fade transition.
  final Duration switchDuration;

  const SkeletonLoader({
    super.key,
    required this.loading,
    required this.child,
    required this.skeleton,
    this.minTime = const Duration(milliseconds: 500),
    this.switchCurve = Curves.easeOut,
    this.switchDuration = const Duration(milliseconds: 300),
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader> {
  /// Whether we are conceptually "showing the skeleton" right now.
  /// This considers both the [widget.loading] state and the [minTime].
  bool _showSkeleton = false;

  Timer? _minTimeTimer;
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    if (widget.loading) {
      _startLoading();
    }
  }

  @override
  void didUpdateWidget(covariant SkeletonLoader oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.loading && !oldWidget.loading) {
      // Switched to loading
      _startLoading();
    } else if (!widget.loading && oldWidget.loading) {
      // Switched to loaded
      _attemptToFinishLoading();
    }
  }

  @override
  void dispose() {
    _minTimeTimer?.cancel();
    super.dispose();
  }

  void _startLoading() {
    setState(() {
      _showSkeleton = true;
      _startTime = DateTime.now();
    });
    // Cancel any existing timer just in case
    _minTimeTimer?.cancel();
  }

  void _attemptToFinishLoading() {
    if (_startTime == null) {
      // Should not happen if logic is correct, but safe fallback
      setState(() => _showSkeleton = false);
      return;
    }

    final elapsed = DateTime.now().difference(_startTime!);
    final remaining = widget.minTime - elapsed;

    if (remaining.isNegative) {
      // Already passed min time
      setState(() => _showSkeleton = false);
    } else {
      // Wait for the remaining time
      _minTimeTimer = Timer(remaining, () {
        if (mounted) {
          setState(() => _showSkeleton = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: widget.switchDuration,
      switchInCurve: widget.switchCurve,
      switchOutCurve: widget.switchCurve,
      child: _showSkeleton
          ? KeyedSubtree(
              key: const ValueKey('skeleton'),
              child: widget.skeleton,
            )
          : KeyedSubtree(
              key: const ValueKey('content'),
              child: widget.child,
            ),
    );
  }
}

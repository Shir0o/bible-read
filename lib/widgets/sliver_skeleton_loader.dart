import 'dart:async';

import 'package:flutter/material.dart';

/// A wrapper that switches between a [skeleton] and a [child] based on
/// [loading] state, while enforcing a [minTime] for the skeleton to be visible.
///
/// This version is specifically designed for Slivers.
/// This prevents the UI from flashing if the content loads very quickly.
class SliverSkeletonLoader extends StatefulWidget {
  /// Whether the content is currently loading.
  final bool loading;

  /// The sliver widget to display when loading is complete.
  final Widget child;

  /// The skeleton sliver widget to display while loading.
  final Widget skeleton;

  /// The minimum time the skeleton should be visible.
  /// Defaults to 500ms.
  final Duration minTime;

  /// Curve for the fade transition between skeleton and content.
  final Curve switchCurve;

  /// Duration for the fade transition.
  final Duration switchDuration;

  const SliverSkeletonLoader({
    super.key,
    required this.loading,
    required this.child,
    required this.skeleton,
    this.minTime = const Duration(milliseconds: 500),
    this.switchCurve = Curves.easeOut,
    this.switchDuration = const Duration(milliseconds: 300),
  });

  @override
  State<SliverSkeletonLoader> createState() => _SliverSkeletonLoaderState();
}

class _SliverSkeletonLoaderState extends State<SliverSkeletonLoader> {
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
  void didUpdateWidget(covariant SliverSkeletonLoader oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.loading && !oldWidget.loading) {
      _startLoading();
    } else if (!widget.loading && oldWidget.loading) {
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
    _minTimeTimer?.cancel();
  }

  void _attemptToFinishLoading() {
    if (_startTime == null) {
      setState(() => _showSkeleton = false);
      return;
    }

    final elapsed = DateTime.now().difference(_startTime!);
    final remaining = widget.minTime - elapsed;

    if (remaining.isNegative) {
      if (mounted) setState(() => _showSkeleton = false);
    } else {
      _minTimeTimer = Timer(remaining, () {
        if (mounted) {
          setState(() => _showSkeleton = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // SliverAnimatedSwitcher is not standard, so we use a CrossBase
    // or simply switch based on state if animation is tricky with Slivers.
    // However, for slivers, switching children might cause scroll jumps.
    // A simple unconditional switch is safest for now, or we can use SliverAnimatedOpacity if needed.
    // Given the request is about timing, let's stick to state switching first.

    // To support animation, we can use SliverCrossFade or similar, but standard Flutter
    // lacks a direct "SliverAnimatedSwitcher".

    // We can use a trick: SliverToBoxAdapter for non-sliver content, but our content IS sliver (SliverList).
    // So we just return the correct sliver.

    return _showSkeleton ? widget.skeleton : widget.child;
  }
}

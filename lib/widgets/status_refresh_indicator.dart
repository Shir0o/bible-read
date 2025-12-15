import 'dart:async';
import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum _RefreshStatus {
  idle,
  loading,
  success,
  error,
}

class StatusRefreshIndicator extends StatefulWidget {
  final Widget child;

  /// Function that performs the refresh. Should throw an exception on failure.
  final Future<void> Function() onRefresh;
  final double maxHeight;

  const StatusRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.maxHeight = 50.0,
  });

  @override
  State<StatusRefreshIndicator> createState() => _StatusRefreshIndicatorState();
}

class _StatusRefreshIndicatorState extends State<StatusRefreshIndicator>
    with SingleTickerProviderStateMixin {
  _RefreshStatus _status = _RefreshStatus.idle;
  late AnimationController _progressController;
  String _message = '';

  @override
  void initState() {
    super.initState();
    // Animation for the "fake" progress bar.
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    // Prevent re-entry if already loading
    if (_status == _RefreshStatus.loading) return;

    if (mounted) {
      setState(() {
        _status = _RefreshStatus.loading;
        _message = 'Refreshing...';
      });
    }

    // Start indeterminate/slow animation
    _progressController.reset();
    _progressController.animateTo(0.95, duration: const Duration(seconds: 10));

    try {
      await widget.onRefresh();

      if (mounted) {
        setState(() {
          _status = _RefreshStatus.success;
          _message = 'Refreshed successfully';
        });
        // Fast finish
        await _progressController.animateTo(1.0,
            duration: const Duration(milliseconds: 300));
        // Keep success state visible
        await Future.delayed(const Duration(seconds: 1));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _RefreshStatus.error;
          _message = 'Refresh failed';
        });
        _progressController.value = 1.0;
        // Keep error state visible
        await Future.delayed(const Duration(seconds: 2));
      }
    } finally {
      if (mounted) {
        setState(() {
          _status = _RefreshStatus.idle;
          _message = '';
          _progressController.reset();
        });
      }
    }
  }

  Color _getBarColor(ColorScheme colorScheme) {
    switch (_status) {
      case _RefreshStatus.success:
        return colorScheme.tertiary;
      case _RefreshStatus.error:
        return colorScheme.error;
      default:
        return colorScheme.primary;
    }
  }

  String _getStatusText(IndicatorController controller) {
    if (_status != _RefreshStatus.idle) {
      return _message;
    }
    if (controller.isArmed) {
      return 'Release to refresh';
    }
    if (controller.isDragging) {
      return 'Pull to refresh';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final barHeight = widget.maxHeight;
    final colorScheme = Theme.of(context).colorScheme;

    return CustomRefreshIndicator(
      offsetToArmed: widget.maxHeight,
      onRefresh: _handleRefresh,
      durations: const RefreshIndicatorDurations(
        settleDuration: Duration.zero,
        cancelDuration: Duration.zero,
      ),
      builder: (context, child, controller) {
        return Stack(
          children: [
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                // Parallax/Push effect: Move child down by the revealed amount
                // Clamp the offset to maxHeight so content doesn't shift too far
                final double offset = (widget.maxHeight * controller.value)
                    .clamp(0.0, widget.maxHeight);
                return Transform.translate(
                  offset: Offset(0, offset),
                  child: child,
                );
              },
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  // Clamp the container height to maxHeight
                  final double containerHeight =
                      (widget.maxHeight * controller.value)
                          .clamp(0.0, widget.maxHeight);

                  // Only show content if we have some height
                  if (containerHeight <= 0) return const SizedBox.shrink();

                  return Container(
                    height: containerHeight,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: OverflowBox(
                      maxHeight: widget.maxHeight,
                      minHeight: widget.maxHeight,
                      alignment: Alignment.topCenter,
                      child: Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          // Progress Bar and Text Area
                          SizedBox(
                            height: barHeight,
                            width: double.infinity,
                            child: Stack(
                              children: [
                                // Progress Bar
                                AnimatedBuilder(
                                  animation: _progressController,
                                  builder: (context, _) {
                                    return SizedBox.expand(
                                      child: LinearProgressIndicator(
                                        value: _status == _RefreshStatus.idle
                                            ? 0
                                            : _progressController.value,
                                        backgroundColor:
                                            colorScheme.surfaceContainerHigh,
                                        valueColor: AlwaysStoppedAnimation(
                                          _getBarColor(colorScheme),
                                        ),
                                        minHeight: barHeight,
                                      ),
                                    );
                                  },
                                ),
                                // Text Overlay
                                Center(
                                  child: Opacity(
                                    opacity: controller.value.clamp(0.0, 1.0),
                                    child: Text(
                                      _getStatusText(controller),
                                      style: AppTheme.textTheme.bodyMedium
                                          ?.copyWith(
                                        color: colorScheme.onSurface,
                                        fontWeight: FontWeight.bold,
                                        shadows: const [
                                          Shadow(
                                            offset: Offset(0, 1),
                                            blurRadius: 2,
                                            color: Colors.black26,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

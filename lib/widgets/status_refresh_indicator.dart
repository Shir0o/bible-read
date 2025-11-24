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
    this.maxHeight = 100.0,
  });

  @override
  State<StatusRefreshIndicator> createState() => _StatusRefreshIndicatorState();
}

class _StatusRefreshIndicatorState extends State<StatusRefreshIndicator>
    with SingleTickerProviderStateMixin {
  _RefreshStatus _status = _RefreshStatus.idle;
  late AnimationController _progressController;
  String _message = 'Release to refresh';

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
          _message = 'Release to refresh';
          _progressController.reset();
        });
      }
    }
  }

  Color _getBarColor() {
    switch (_status) {
      case _RefreshStatus.success:
        return Colors.greenAccent;
      case _RefreshStatus.error:
        return Colors.redAccent;
      default:
        return AppTheme.colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final barHeight = widget.maxHeight / 2;

    return CustomRefreshIndicator(
      onRefresh: _handleRefresh,
      builder: (context, child, controller) {
        return Stack(
          children: [
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                // Parallax/Push effect: Move child down by the revealed amount
                final double offset = (widget.maxHeight * controller.value);
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
                  final double containerHeight =
                      widget.maxHeight * controller.value;

                  // Only show content if we have some height
                  if (containerHeight <= 0) return const SizedBox.shrink();

                  return Container(
                    height: containerHeight,
                    width: double.infinity,
                    color: AppTheme.backgroundColor,
                    child: OverflowBox(
                      maxHeight: widget.maxHeight,
                      minHeight: widget.maxHeight,
                      alignment: Alignment.topCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Expanded(
                            child: Center(
                              child: Opacity(
                                opacity: controller.value.clamp(0.0, 1.0),
                                child: Text(
                                  _status == _RefreshStatus.idle && controller.isDragging
                                      ? 'Release to refresh'
                                      : _message,
                                  style: AppTheme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: barHeight,
                            width: double.infinity,
                            child: AnimatedBuilder(
                              animation: _progressController,
                              builder: (context, _) {
                                return LinearProgressIndicator(
                                  value: _status == _RefreshStatus.idle
                                      ? 0
                                      : _progressController.value,
                                  backgroundColor: Colors.white10,
                                  valueColor: AlwaysStoppedAnimation(
                                    _getBarColor(),
                                  ),
                                  minHeight: barHeight,
                                );
                              },
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

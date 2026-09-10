import 'dart:async';

import 'package:flutter/material.dart';

/// Coalesces rapid mark-as-read actions into a single undoable burst.
///
/// Each mark calls [add] with an undo callback. Marks within [window] of the
/// previous one merge into the same burst: the toast's count grows, its timer
/// resets, and one Undo reverts the whole burst. When the window elapses the
/// toast is dismissed and the burst is committed.
///
/// The controller owns the SnackBar lifecycle: it shows the floating toast on
/// the first mark, updates its count in place on subsequent marks (via a
/// [ValueListenableBuilder] content), and dismisses it when the burst ends.
/// [dispose] must be called from the host's dispose.
///
/// Burst-scoped coupling state ([couplingFiredInBurst], [habitBeforeBurst]) is
/// set by the host around the reading→habit coupling and read by the undo
/// closures, so a burst undo can revert today's habit record exactly when the
/// burst caused it (ADR-0005).
class BurstUndoController {
  BurstUndoController({
    this.window = const Duration(seconds: 4),
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  /// How long a burst stays undoable after the last mark.
  final Duration window;

  /// Bottom margin for the floating toast, keeping it clear of bottom-anchored
  /// controls (the app's bottom nav, the plan hub's action buttons).
  final EdgeInsets margin;

  /// Whether the current burst's marks caused today's habit to be recorded
  /// (the reading→habit coupling). Set by the host after coupling fires; read
  /// by the burst's undo closures to decide whether to revert the habit.
  bool couplingFiredInBurst = false;

  /// Whether today's habit was already recorded before the burst started.
  /// Set by the host at burst start; the undo reverts the habit only when
  /// this is false and [couplingFiredInBurst] is true.
  bool habitBeforeBurst = false;

  final List<VoidCallback> _undoActions = [];
  final ValueNotifier<int> _count = ValueNotifier(0);
  Timer? _timer;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _controller;
  bool _disposed = false;

  /// Number of marks in the current burst (0 when idle).
  int get count => _undoActions.length;

  /// Registers a mark and (re)shows the coalesced undo toast.
  void add(BuildContext context, VoidCallback undo) {
    if (_disposed) return;
    _undoActions.add(undo);
    _count.value = _undoActions.length;
    _timer?.cancel();
    _timer = Timer(window, _dismiss);

    if (_controller == null) {
      final messenger = ScaffoldMessenger.of(context);
      // A fresh burst replaces whatever toast is up (e.g. the daily-habit
      // toast) so the burst's undo window starts immediately.
      messenger.hideCurrentSnackBar();
      final controller = messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: margin,
          // The real dismissal is the burst timer; this long duration is only
          // a safety cap so the toast never outlives the controller.
          duration: const Duration(minutes: 1),
          content: ValueListenableBuilder<int>(
            valueListenable: _count,
            builder: (context, count, _) => Text(
              count == 1
                  ? 'Reading marked as read'
                  : '$count readings marked as read',
            ),
          ),
          action: SnackBarAction(label: 'Undo', onPressed: _undoAll),
        ),
      );
      _controller = controller;
      // If something else dismisses the toast (e.g. another screen's
      // hideCurrentSnackBar), forget it so the next mark shows a fresh one.
      controller.closed.whenComplete(() {
        if (identical(_controller, controller)) _controller = null;
      });
    }
  }

  void _undoAll() {
    if (_disposed) return;
    _timer?.cancel();
    final actions = List<VoidCallback>.from(_undoActions);
    _undoActions.clear();
    _count.value = 0;
    _controller?.close();
    _controller = null;
    // LIFO: each action reverts its own mark from the state as of that mark,
    // so the last mark must be reverted first.
    for (final action in actions.reversed) {
      action();
    }
    couplingFiredInBurst = false;
    habitBeforeBurst = false;
  }

  void _dismiss() {
    if (_disposed) return;
    _timer?.cancel();
    _controller?.close();
    _controller = null;
    _undoActions.clear();
    _count.value = 0;
    couplingFiredInBurst = false;
    habitBeforeBurst = false;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _controller?.close();
    _controller = null;
    _undoActions.clear();
    _count.dispose();
  }
}

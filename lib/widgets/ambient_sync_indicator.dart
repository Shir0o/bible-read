import 'dart:async';
import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import 'common_styles.dart';

enum _SyncVisualState {
  hidden,
  savedLocally,
  allSynced,
}

/// An ambient pill indicating offline and sync status in the header.
///
/// Adheres to Sanctuary Liturgy aesthetic:
/// - When offline with changes or offline in general: a warm liturgical beeswax
///   gold dot with "Saved locally".
/// - When returning online and synced: transitions smoothly to a quiet checkmark
///   with "All synced", displays for [syncedDuration] (default 2.5s), and fades out.
/// - When online and synced: hidden, preserving the uncluttered sacred space.
class AmbientSyncIndicator extends StatefulWidget {
  final ConnectivityService? connectivityService;
  final Stream<ConnectionStatus>? statusStream;
  final ConnectionStatus? initialStatus;
  final bool? hasPendingWrites;
  final Duration syncedDuration;

  const AmbientSyncIndicator({
    super.key,
    this.connectivityService,
    this.statusStream,
    this.initialStatus,
    this.hasPendingWrites,
    this.syncedDuration = const Duration(milliseconds: 2500),
  });

  @override
  State<AmbientSyncIndicator> createState() => _AmbientSyncIndicatorState();
}

class _AmbientSyncIndicatorState extends State<AmbientSyncIndicator> {
  StreamSubscription<ConnectionStatus>? _sub;
  ConnectionStatus _connectionStatus = ConnectionStatus.online;
  _SyncVisualState _state = _SyncVisualState.hidden;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _connectionStatus = widget.initialStatus ?? ConnectionStatus.online;
    if (_connectionStatus == ConnectionStatus.offline ||
        (widget.hasPendingWrites ?? false)) {
      _state = _SyncVisualState.savedLocally;
    }
    _listenToStatus();
  }

  void _listenToStatus() {
    final stream = widget.statusStream ?? widget.connectivityService?.status;
    if (stream != null) {
      _sub = stream.listen(_handleStatusChange);
    }
  }

  void _handleStatusChange(ConnectionStatus status) {
    if (!mounted) return;
    final previousStatus = _connectionStatus;
    _connectionStatus = status;

    if (status == ConnectionStatus.offline) {
      _hideTimer?.cancel();
      setState(() {
        _state = _SyncVisualState.savedLocally;
      });
    } else if (status == ConnectionStatus.online) {
      if (previousStatus == ConnectionStatus.offline ||
          _state == _SyncVisualState.savedLocally) {
        if (widget.hasPendingWrites ?? false) {
          return;
        }
        _transitionToSynced();
      }
    }
  }

  void _transitionToSynced() {
    _hideTimer?.cancel();
    setState(() {
      _state = _SyncVisualState.allSynced;
    });
    _hideTimer = Timer(widget.syncedDuration, () {
      if (!mounted) return;
      setState(() {
        _state = _SyncVisualState.hidden;
      });
    });
  }

  @override
  void didUpdateWidget(covariant AmbientSyncIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.statusStream != oldWidget.statusStream ||
        widget.connectivityService != oldWidget.connectivityService) {
      _sub?.cancel();
      _listenToStatus();
    }

    final hadPending = oldWidget.hasPendingWrites ?? false;
    final hasPending = widget.hasPendingWrites ?? false;

    if (!hadPending && hasPending) {
      _hideTimer?.cancel();
      setState(() {
        _state = _SyncVisualState.savedLocally;
      });
    } else if (hadPending && !hasPending) {
      if (_connectionStatus == ConnectionStatus.online &&
          _state == _SyncVisualState.savedLocally) {
        _transitionToSynced();
      }
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      label: _state == _SyncVisualState.savedLocally
          ? 'Changes saved locally, offline'
          : _state == _SyncVisualState.allSynced
              ? 'All changes synced'
              : null,
      readOnly: true,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _buildContent(context, colorScheme),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme colorScheme) {
    switch (_state) {
      case _SyncVisualState.hidden:
        return const SizedBox.shrink(key: ValueKey('ambient_sync_hidden'));
      case _SyncVisualState.savedLocally:
        return Container(
          key: const ValueKey('ambient_sync_saved_locally'),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gap8,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppSpacing.rPill),
            border: Border.all(
              color: colorScheme.tertiary.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: colorScheme.tertiary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.gap6),
              Text(
                'Saved locally',
                style: AppTextStyles.caption(context).copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        );
      case _SyncVisualState.allSynced:
        return Container(
          key: const ValueKey('ambient_sync_all_synced'),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gap8,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppSpacing.rPill),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_rounded,
                size: 13,
                color: colorScheme.tertiary,
              ),
              const SizedBox(width: AppSpacing.gap4),
              Text(
                'All synced',
                style: AppTextStyles.caption(context).copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        );
    }
  }
}

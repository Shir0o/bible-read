import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/skeleton_loader.dart';
import '../widgets/skeleton.dart';
import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/friend_avatar.dart';
import '../widgets/sub_header.dart';
import '../theme/app_theme.dart';

/// Page displaying pending join requests for a specific group.
class GroupJoinRequestsPage extends StatefulWidget {
  /// Firestore-backed service to manage groups.
  final GroupService groupService;

  /// Firebase auth instance used to identify the current user if needed.
  final FirebaseAuth auth;

  /// Group id whose join requests to display.
  final String groupId;

  /// Optional vibration service for haptics.
  final VibrationService vibrationService;

  /// Optional override for the underlying join request stream, primarily used in tests.
  final Stream<QuerySnapshot<Map<String, dynamic>>>? joinRequestsStream;

  GroupJoinRequestsPage({
    super.key,
    required this.groupId,
    this.joinRequestsStream,
    GroupService? groupService,
    FirebaseAuth? auth,
    VibrationService? vibrationService,
  })  : groupService = groupService ?? GroupService(),
        auth = auth ?? FirebaseAuth.instance,
        vibrationService = vibrationService ?? const VibrationService();

  @override
  State<GroupJoinRequestsPage> createState() => _GroupJoinRequestsPageState();
}

class _GroupJoinRequestsPageState extends State<GroupJoinRequestsPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _requests =
      widget.joinRequestsStream ??
          widget.groupService.firestore
              .collection(GroupCollections.groups)
              .doc(widget.groupId)
              .collection(GroupCollections.joinRequests)
              .snapshots();

  /// Requests acted on locally: hidden at once (optimistic), restored if the
  /// write fails, and dropped once the stream no longer carries them.
  final Set<String> _handled = {};

  Future<void> _respond(String uid, {required bool approve}) async {
    setState(() => _handled.add(uid));
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (approve) {
        await widget.groupService.approveJoinRequest(
          groupId: widget.groupId,
          uid: uid,
        );
      } else {
        await widget.groupService.denyJoinRequest(
          groupId: widget.groupId,
          uid: uid,
        );
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(approve ? 'Request approved' : 'Request denied'),
        ),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to ${approve ? 'approve' : 'deny'} request: $e');
      }
      ErrorLogger.log(e, st);
      if (mounted) setState(() => _handled.remove(uid));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              approve ? 'Failed to approve request' : 'Failed to deny request'),
        ),
      );
    }
  }

  /// "Asked …" age of a request: minutes, hours, yesterday or N days ago.
  static String _askedAgo(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) {
      final m = diff.inMinutes;
      return '$m ${m == 1 ? 'minute' : 'minutes'} ago';
    }
    if (diff.inDays < 1) {
      final h = diff.inHours;
      return '$h ${h == 1 ? 'hour' : 'hours'} ago';
    }
    if (diff.inDays == 1) return 'yesterday';
    return '${diff.inDays} days ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SubHeader(
              title: 'Join requests',
              onBack: () {
                unawaited(widget.vibrationService.lightImpact());
                Navigator.of(context).pop();
              },
            ),
            Expanded(
              child: Container(
                decoration: CommonStyles.backgroundDecoration(
                  Theme.of(context).colorScheme,
                ),
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _requests,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Center(
                          child: Text('Failed to load join requests'));
                    }
                    return SnapshotSkeleton<
                        QuerySnapshot<Map<String, dynamic>>>(
                      snapshot: snapshot,
                      skeleton: const _JoinRequestsSkeleton(),
                      builder: (context, snap) {
                        final present = {
                          for (final d in snap.docs)
                            d.data()['uid'] as String? ?? d.id,
                        };
                        // The stream has caught up with these; stop
                        // overriding.
                        _handled.removeWhere((uid) => !present.contains(uid));
                        final requests = snap.docs
                            .where((d) => !_handled
                                .contains(d.data()['uid'] as String? ?? d.id))
                            .toList();
                        if (requests.isEmpty) return const _AllCaughtUp();
                        return _buildList(context, requests);
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> requests,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final muted = colorScheme.onSurfaceVariant;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.gap16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.gap12,
              vertical: AppSpacing.gap4,
            ),
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(AppSpacing.rPill),
            ),
            child: Text(
              '${requests.length} waiting',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onTertiaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.gap8),
        Text(
          'Once you welcome someone in, they\'ll see what the group has read '
          'and can send encouragement.',
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: AppSpacing.gap12),
        for (final d in requests) _requestCard(context, d),
        const SizedBox(height: AppSpacing.gap12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.gap2),
              child: Icon(Icons.lock_outline, size: 14, color: muted),
            ),
            const SizedBox(width: AppSpacing.gap6),
            Expanded(
              child: Text(
                '“Not now” quietly removes the request. They aren\'t told.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _requestCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final theme = Theme.of(context);
    final data = d.data();
    final uid = data['uid'] as String? ?? d.id;
    final name = data['name'] as String? ?? '';
    final requestedAt = data['requestedAt'];
    final askedAt = requestedAt is Timestamp ? requestedAt.toDate() : null;
    return CommonStyles.buildCard(
      context: context,
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.gap6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FriendAvatar(
                name: name.isEmpty ? uid : name,
                photoUrl: data['photoUrl'] as String?,
                radius: 24,
              ),
              const SizedBox(width: AppSpacing.gap12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? uid : name,
                      style: theme.textTheme.titleLarge,
                    ),
                    if (askedAt != null) ...[
                      const SizedBox(height: AppSpacing.gap2),
                      Text(
                        'Asked ${_askedAgo(askedAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: 'Deny join request from $name',
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: () => _respond(uid, approve: false),
                      child: const Text('Not now'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.gap12),
              Expanded(
                child: Semantics(
                  label: 'Approve join request from $name',
                  child: SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: () => _respond(uid, approve: true),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Welcome in'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Empty state: nobody is waiting.
class _AllCaughtUp extends StatelessWidget {
  const _AllCaughtUp();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.gap32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 136,
              height: 136,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.of(context).border),
              ),
              child: Icon(
                Icons.door_front_door_outlined,
                size: 48,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.gap24),
            Text(
              'All caught up',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.gap8),
            Text(
              'No one is waiting at the door. When someone asks to join, '
              'they\'ll show up here.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder shaped like the request cards: avatar, name and age lines,
/// and the two action buttons.
class _JoinRequestsSkeleton extends StatelessWidget {
  const _JoinRequestsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.gap16),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final nameWidth in const [140.0, 110.0, 160.0])
          CommonStyles.buildCard(
            context: context,
            margin: const EdgeInsets.symmetric(vertical: AppSpacing.gap6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Skeleton(
                        width: 48, height: 48, shape: CircleBorder()),
                    const SizedBox(width: AppSpacing.gap12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Skeleton(width: nameWidth, height: 16),
                        const SizedBox(height: AppSpacing.gap8),
                        const Skeleton(width: 90, height: 12),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    Expanded(child: Skeleton(height: 44)),
                    SizedBox(width: AppSpacing.gap12),
                    Expanded(child: Skeleton(height: 44)),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

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
import '../widgets/sub_header.dart';
import '../theme/app_theme.dart';

/// Page displaying pending join requests for a specific group.
class GroupJoinRequestsPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SubHeader(
              title: 'Join Requests',
              onBack: () {
                unawaited(vibrationService.lightImpact());
                Navigator.of(context).pop();
              },
            ),
            Expanded(
              child: Container(
                decoration: CommonStyles.backgroundDecoration(
                  Theme.of(context).colorScheme,
                ),
                padding: const EdgeInsets.all(AppSpacing.gap16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Approving a request lets the newcomer see what everyone in the '
                      'group has read, and send them encouragement.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.gap12),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: joinRequestsStream ??
                            groupService.firestore
                                .collection(GroupCollections.groups)
                                .doc(groupId)
                                .collection(GroupCollections.joinRequests)
                                .snapshots(),
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
                              final requests = snap.docs;
                              if (requests.isEmpty) {
                                return const Center(
                                    child: Text('No pending requests'));
                              }
                              return ListView.builder(
                                itemCount: requests.length,
                                itemBuilder: (context, i) {
                                  final d = requests[i];
                                  final data = d.data();
                                  final uid = data['uid'] as String? ?? d.id;
                                  final name = data['name'] as String? ?? '';
                                  return CommonStyles.buildTappableCard(
                                    context: context,
                                    onTap: () {},
                                    margin: const EdgeInsets.symmetric(
                                        vertical: AppSpacing.gap4),
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(name.isEmpty ? uid : name),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Semantics(
                                            label:
                                                'Approve join request from $name',
                                            child: IconButton(
                                              icon: const Icon(Icons.check),
                                              tooltip: 'Approve',
                                              onPressed: () async {
                                                try {
                                                  await groupService
                                                      .approveJoinRequest(
                                                    groupId: groupId,
                                                    uid: uid,
                                                  );
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                            'Request approved'),
                                                      ),
                                                    );
                                                  }
                                                } catch (e, st) {
                                                  if (kDebugMode) {
                                                    debugPrint(
                                                        'Failed to approve request: $e');
                                                  }
                                                  ErrorLogger.log(e, st);
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'Failed to approve request',
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                }
                                              },
                                            ),
                                          ),
                                          Semantics(
                                            label:
                                                'Deny join request from $name',
                                            child: IconButton(
                                              icon: const Icon(Icons.close),
                                              tooltip: 'Deny',
                                              onPressed: () async {
                                                try {
                                                  await groupService
                                                      .denyJoinRequest(
                                                    groupId: groupId,
                                                    uid: uid,
                                                  );
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                            'Request denied'),
                                                      ),
                                                    );
                                                  }
                                                } catch (e, st) {
                                                  if (kDebugMode) {
                                                    debugPrint(
                                                        'Failed to deny request: $e');
                                                  }
                                                  ErrorLogger.log(e, st);
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                            'Failed to deny request'),
                                                      ),
                                                    );
                                                  }
                                                }
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder shaped like the request cards: a name and two action icons.
class _JoinRequestsSkeleton extends StatelessWidget {
  const _JoinRequestsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final nameWidth in const [140.0, 110.0, 160.0])
          CommonStyles.buildCard(
            context: context,
            margin: const EdgeInsets.symmetric(vertical: AppSpacing.gap4),
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  Skeleton(width: nameWidth, height: 14),
                  const Spacer(),
                  const Skeleton(width: 28, height: 28, shape: CircleBorder()),
                  const SizedBox(width: AppSpacing.gap20),
                  const Skeleton(width: 28, height: 28, shape: CircleBorder()),
                  const SizedBox(width: AppSpacing.gap12),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/error_logger.dart';
import '../services/group_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';

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
  }) : groupService = groupService ?? GroupService(),
       auth = auth ?? FirebaseAuth.instance,
       vibrationService = vibrationService ?? const VibrationService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar(
        context,
        'Join Requests',
        leading: BackButton(
          onPressed: () {
            unawaited(vibrationService.lightImpact());
            Navigator.of(context).pop();
          },
        ),
        automaticallyImplyLeading: true,
      ),
      body: Container(
        decoration: CommonStyles.backgroundDecoration(
          Theme.of(context).colorScheme,
        ),
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream:
              joinRequestsStream ??
              groupService.firestore
                  .collection(GroupCollections.groups)
                  .doc(groupId)
                  .collection(GroupCollections.joinRequests)
                  .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('Failed to load join requests'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final requests = snapshot.data!.docs;
            if (requests.isEmpty) {
              return const Center(child: Text('No pending requests'));
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
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(name.isEmpty ? uid : name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          label: 'Approve join request from $name',
                          child: IconButton(
                            icon: const Icon(Icons.check),
                            tooltip: 'Approve',
                            onPressed: () async {
                              try {
                                await groupService.approveJoinRequest(
                                  groupId: groupId,
                                  uid: uid,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Request approved'),
                                    ),
                                  );
                                }
                              } catch (e, st) {
                                if (kDebugMode) {
                                  debugPrint('Failed to approve request: $e');
                                }
                                ErrorLogger.log(e, st);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
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
                          label: 'Deny join request from $name',
                          child: IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Deny',
                            onPressed: () async {
                              try {
                                await groupService.denyJoinRequest(
                                  groupId: groupId,
                                  uid: uid,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Request denied'),
                                    ),
                                  );
                                }
                              } catch (e, st) {
                                if (kDebugMode) {
                                  debugPrint('Failed to deny request: $e');
                                }
                                ErrorLogger.log(e, st);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Failed to deny request'),
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
        ),
      ),
    );
  }
}

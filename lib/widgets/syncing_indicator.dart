import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SyncingIndicator extends StatelessWidget {
  final FirebaseFirestore firestore;
  final String userId;

  const SyncingIndicator({
    super.key,
    required this.firestore,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    // We listen to the user's main document with metadata changes.
    // While it won't capture ALL pending writes in the system, it's a good proxy
    // for whether Firestore is currently working on syncing data for this user.
    return StreamBuilder<DocumentSnapshot>(
      stream: firestore
          .collection('users')
          .doc(userId)
          .snapshots(includeMetadataChanges: true),
      builder: (context, snapshot) {
        final hasPendingWrites = snapshot.data?.metadata.hasPendingWrites ?? false;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: hasPendingWrites
              ? Container(
                  key: const ValueKey('syncing'),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Syncing...',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('not_syncing')),
        );
      },
    );
  }
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/badge_award.dart';
import 'group_collections.dart';

/// Reads the badges shown on the Journey tab.
///
/// Badges live at `users/{uid}/achievements/{id}` and are awarded only by the
/// server (`functions/badge-awarding.js`); the security rules deny every
/// client write, including the owner's.
class BadgeService {
  BadgeService({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore firestore;

  CollectionReference<Map<String, dynamic>> _collection(String uid) =>
      firestore.collection('users').doc(uid).collection('achievements');

  /// Streams every badge [uid] has been awarded.
  Stream<List<BadgeAward>> watch(String uid) => _collection(uid)
      .snapshots()
      .map((snap) => snap.docs.map(BadgeAward.fromFirestore).toList());

  /// Streams the latest badge per member across [groupIds]' mirrors at
  /// `groups/{g}/badges/{uid}` — the co-member-readable path (ADR-0004).
  /// One live stream per Group, merged by uid; when the same member is
  /// mirrored in several Groups the newest [BadgeMirror.dateUnlocked] wins.
  /// Empty for no Groups.
  Stream<Map<String, BadgeMirror>> watchForGroups(List<String> groupIds) {
    if (groupIds.isEmpty) {
      return Stream.value(const <String, BadgeMirror>{});
    }

    return Stream<Map<String, BadgeMirror>>.multi((controller) {
      final latest = <String, Map<String, BadgeMirror>>{
        for (final id in groupIds) id: <String, BadgeMirror>{},
      };
      final reported = <String>{};

      void emit() {
        if (controller.isClosed) return;
        final merged = <String, BadgeMirror>{};
        for (final mirrors in latest.values) {
          for (final mirror in mirrors.values) {
            final held = merged[mirror.uid];
            if (held == null ||
                (mirror.dateUnlocked ?? DateTime.fromMillisecondsSinceEpoch(0))
                    .isAfter(held.dateUnlocked ??
                        DateTime.fromMillisecondsSinceEpoch(0))) {
              merged[mirror.uid] = mirror;
            }
          }
        }
        controller.add(merged);
      }

      final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
      for (final groupId in groupIds) {
        final sub = firestore
            .collection(GroupCollections.groups)
            .doc(groupId)
            .collection('badges')
            .snapshots()
            .listen(
          (snap) {
            latest[groupId] = {
              for (final doc in snap.docs)
                doc.id: BadgeMirror.fromFirestore(doc.id, doc),
            };
            reported.add(groupId);
            emit();
          },
          onError: (Object e, StackTrace st) {
            latest[groupId] = {};
            reported.add(groupId);
            if (reported.length == groupIds.length) {
              controller.addError(e, st);
            } else {
              emit();
            }
          },
        );
        subs.add(sub);
      }

      controller.onCancel = () {
        for (final sub in subs) {
          unawaited(sub.cancel());
        }
      };
    });
  }
}

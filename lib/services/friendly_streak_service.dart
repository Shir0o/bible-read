import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/friend_streak_link.dart';
import 'error_logger.dart';
import 'friend_service.dart';

/// Summary of a user's paired streak links and invites.
class FriendlyStreakLinksSummary {
  /// Creates a [FriendlyStreakLinksSummary].
  const FriendlyStreakLinksSummary({
    required this.activeLinks,
    required this.pendingLinks,
  });

  /// Active streak partners sorted by current streak descending.
  final List<FriendStreakLink> activeLinks;

  /// Pending invites waiting for approval or acceptance.
  final List<FriendStreakLink> pendingLinks;

  /// Empty summary instance.
  static const FriendlyStreakLinksSummary empty = FriendlyStreakLinksSummary(
    activeLinks: [],
    pendingLinks: [],
  );

  /// Whether the user has any links or invites.
  bool get hasPartners => activeLinks.isNotEmpty || pendingLinks.isNotEmpty;
}

/// Loads friendly streak metrics derived from the user's friends list.
class FriendlyStreakService {
  /// Firestore instance used to read friend summaries.
  final FirebaseFirestore firestore;

  FriendlyStreakService({FirebaseFirestore? firestore})
    : firestore = firestore ?? FirebaseFirestore.instance;

  /// Returns the active streak links and pending invites for the given [uid].
  ///
  /// Returns an empty summary when no data is found or when the query fails.
  Future<FriendlyStreakLinksSummary> fetchLinks(String uid) async {
    try {
      final linksFuture = _linksRef(uid).get();
      final invitesFuture = _invitesRef(uid).get();
      final results = await Future.wait([linksFuture, invitesFuture]);

      final activeLinks =
          results[0].docs
              .map((doc) => FriendStreakLink.fromDoc(doc, ownerUid: uid))
              .where((link) => link.isActive)
              .toList()
            ..sort((a, b) => b.currentStreak.compareTo(a.currentStreak));

      final pendingLinks =
          results[1].docs
              .map((doc) => FriendStreakLink.fromDoc(doc, ownerUid: uid))
              .where((link) => link.isPending)
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      return FriendlyStreakLinksSummary(
        activeLinks: activeLinks,
        pendingLinks: pendingLinks,
      );
    } catch (e, st) {
      ErrorLogger.log(e, st);
      return FriendlyStreakLinksSummary.empty;
    }
  }

  CollectionReference<Map<String, dynamic>> _linksRef(String uid) {
    return firestore
        .collection(FriendCollections.users)
        .doc(uid)
        .collection(FriendCollections.friendStreakLinks);
  }

  CollectionReference<Map<String, dynamic>> _invitesRef(String uid) {
    return firestore
        .collection(FriendCollections.users)
        .doc(uid)
        .collection(FriendCollections.friendStreakInvites);
  }
}

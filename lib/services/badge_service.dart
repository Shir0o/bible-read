import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/badge_award.dart';
import '../models/read_through.dart';

/// Awards and reads the badges shown on the Journey tab.
///
/// Badges live at `users/{uid}/achievements/{id}` — the collection the app has
/// always written first-reader and first-book awards to.
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

  /// Awards any read-through badge [counts] has newly earned.
  ///
  /// Idempotent: a badge already held is left alone, so its original unlock
  /// date survives.
  Future<List<BadgeDefinition>> awardFor(
    String uid,
    ReadThroughCounts counts,
  ) async {
    final held = (await _collection(uid).get()).docs.map((d) => d.id).toSet();

    final newly = BadgeDefinition.all
        .where((b) => b.isEarnedBy(counts) && !held.contains(b.id))
        .toList();
    if (newly.isEmpty) return const [];

    final batch = firestore.batch();
    for (final badge in newly) {
      batch.set(_collection(uid).doc(badge.id), {
        'title': badge.title,
        'type': 'read_through',
        'dateUnlocked': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return newly;
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/badge_award.dart';

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
}

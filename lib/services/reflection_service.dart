import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/reflection.dart';

/// Service for reading and writing a user's private daily reflections.
///
/// Kept as its own `reflections` subcollection (rather than fields on the
/// `reading` doc) so it never races with the optimistic mark-as-read/undo
/// writes in `HomePage._toggleReadStatus`.
class ReflectionService {
  /// Firestore instance.
  final FirebaseFirestore firestore;

  /// Creates a [ReflectionService].
  ReflectionService({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid, String dateKey) =>
      firestore
          .collection('users')
          .doc(uid)
          .collection('reflections')
          .doc(dateKey);

  /// Fetches the reflection saved for [dateKey], or `null` if none exists.
  Future<Reflection?> fetchReflection(String uid, String dateKey) async {
    final doc = await _doc(uid, dateKey).get();
    return Reflection.fromFirestore(doc);
  }

  /// Saves [text] as the reflection for [dateKey]. An empty/blank [text]
  /// deletes the reflection instead, so clearing the field in the editor
  /// behaves the same as skipping.
  Future<void> saveReflection(String uid, String dateKey, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      await deleteReflection(uid, dateKey);
      return;
    }
    await _doc(uid, dateKey).set({
      'text': trimmed,
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  /// Deletes the reflection saved for [dateKey], if any.
  Future<void> deleteReflection(String uid, String dateKey) async {
    await _doc(uid, dateKey).delete();
  }
}

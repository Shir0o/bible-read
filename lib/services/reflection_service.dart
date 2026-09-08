import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/reflection.dart';
import 'group_collections.dart';

/// Service for reading and writing a user's private daily reflections.
///
/// Kept as its own `reflections` subcollection (rather than fields on the
/// `reading` doc) so it never races with the optimistic mark-as-read/undo
/// writes in `HomePage._toggleReadStatus`.
///
/// Sharing (#807) copies the opted-in text onto the author's read-log entry
/// for that day in every Group they belong to (ADR-0004) — the already
/// co-member-readable object. The private document is never made readable:
/// the owner-only rule on `reflections` survives unchanged. Unsharing
/// deletes the copied text from the entries; the private original is
/// untouched by all three operations (share, unshare, edit).
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

  /// Firestore document id for [date] — the same key the read log uses.
  static String dateKeyFor(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Fetches the reflection saved for [dateKey], or `null` if none exists.
  Future<Reflection?> fetchReflection(String uid, String dateKey) async {
    final doc = await _doc(uid, dateKey).get();
    return Reflection.fromFirestore(doc);
  }

  /// Saves [text] as the reflection for [dateKey]. An empty/blank [text]
  /// deletes the reflection instead, so clearing the field in the editor
  /// behaves the same as skipping.
  ///
  /// [share] decides whether the text is copied onto the day's read-log
  /// entries for the Circle to read. Saving with `share: false` after a
  /// shared save is an unshare: the copy is removed and the private
  /// original is updated in place. Saving with `share: true` over an
  /// already-shared entry updates the copy without touching its shared
  /// state — editing never unshares.
  Future<void> saveReflection(
    String uid,
    String dateKey,
    String text, {
    bool share = false,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      await deleteReflection(uid, dateKey);
      return;
    }
    await _doc(uid, dateKey).set({
      'text': trimmed,
      'updatedAt': Timestamp.now(),
      'shared': share,
    }, SetOptions(merge: true));
    await _syncSharedCopy(uid, dateKey, share ? trimmed : null);
  }

  /// Deletes the reflection saved for [dateKey], if any, together with any
  /// copy shared onto the read log.
  Future<void> deleteReflection(String uid, String dateKey) async {
    await _doc(uid, dateKey).delete();
    await _syncSharedCopy(uid, dateKey, null);
  }

  /// Writes [text] onto (or removes it from) the author's read-log entry for
  /// [dateKey] in every Group they belong to. `null` removes the copy —
  /// unsharing deletes the text, it does not hide it behind a flag.
  ///
  /// A reader with no Groups has no read-log entries to carry the copy and
  /// nothing is written.
  Future<void> _syncSharedCopy(
    String uid,
    String dateKey,
    String? text,
  ) async {
    final memberships = await firestore
        .collectionGroup('members')
        .where('uid', isEqualTo: uid)
        .get();
    final groupIds = memberships.docs
        .map((doc) => doc.reference.parent.parent?.id)
        .whereType<String>()
        .toSet()
        .toList();
    if (groupIds.isEmpty) return;

    final batch = firestore.batch();
    for (final groupId in groupIds) {
      final entry = firestore
          .collection(GroupCollections.groups)
          .doc(groupId)
          .collection('read_log')
          .doc(dateKey)
          .collection('entries')
          .doc(uid);
      if (text == null) {
        batch.update(entry, {
          'sharedReflection': FieldValue.delete(),
        });
      } else {
        batch.set(
          entry,
          {'sharedReflection': text},
          SetOptions(merge: true),
        );
      }
    }
    await batch.commit();
  }
}

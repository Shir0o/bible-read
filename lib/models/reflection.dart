import 'package:cloud_firestore/cloud_firestore.dart';

/// A user's private journal entry for a single day, keyed by date.
class Reflection {
  /// Reflection text.
  final String text;

  /// Time the reflection was last saved.
  final DateTime updatedAt;

  /// Creates a [Reflection].
  const Reflection({required this.text, required this.updatedAt});

  /// Reads a [Reflection] from a Firestore document, or `null` if the
  /// document doesn't exist or has no text.
  static Reflection? fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;
    final text = data['text'] as String?;
    if (text == null || text.isEmpty) return null;
    final ts = data['updatedAt'];
    return Reflection(
      text: text,
      updatedAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }

  /// Serializes this reflection for Firestore.
  Map<String, dynamic> toFirestore() => {
        'text': text,
        'updatedAt': Timestamp.fromDate(updatedAt),
      };
}

import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single comment within the app.
class Comment {
  /// Unique document id of the comment.
  final String id;

  /// UID of the user who posted the comment.
  final String uid;

  /// Display name of the comment author.
  final String authorName;

  /// Message body of the comment.
  final String message;

  /// Time the comment was created.
  final DateTime timestamp;

  /// Creates a [Comment].
  const Comment({
    required this.id,
    required this.uid,
    required this.authorName,
    required this.message,
    required this.timestamp,
  });

  /// Reads a [Comment] from a Firestore document.
  factory Comment.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data['timestamp'];
    return Comment(
      id: doc.id,
      uid: data['uid'] as String? ?? '',
      authorName: data['authorName'] as String? ?? '',
      message: data['message'] as String? ?? '',
      timestamp: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }

  /// Parses a [Comment] from JSON.
  factory Comment.fromJson(Map<String, dynamic> json) {
    final ts = json['timestamp'];
    return Comment(
      id: json['id'] as String? ?? '',
      uid: json['uid'] as String? ?? '',
      authorName: json['authorName'] as String? ?? '',
      message: json['message'] as String? ?? '',
      timestamp: ts is String
          ? DateTime.tryParse(ts) ?? DateTime.now()
          : ts is int
          ? DateTime.fromMillisecondsSinceEpoch(ts)
          : DateTime.now(),
    );
  }

  /// Serializes this comment for Firestore.
  Map<String, dynamic> toFirestore() => {
    'uid': uid,
    'authorName': authorName,
    'message': message,
    'timestamp': Timestamp.fromDate(timestamp),
  };

  /// Converts this comment to JSON.
  Map<String, dynamic> toJson() => {
    'id': id,
    'uid': uid,
    'authorName': authorName,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
  };
}

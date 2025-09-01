import 'package:cloud_firestore/cloud_firestore.dart';

import 'comment.dart';

/// Represents a single read log entry.
class ReadLog {
  /// UID of the user who read.
  final String uid;

  /// Display name of the reader.
  final String name;

  /// Names of users who liked this entry.
  final List<String> likeNames;

  /// Comments left on this entry.
  final List<Comment> comments;

  /// Whether the current user has liked this entry.
  final bool liked;

  /// Whether this entry belongs to the first reader of the day.
  final bool firstReader;

  const ReadLog({
    required this.uid,
    required this.name,
    required this.likeNames,
    required this.comments,
    required this.liked,
    required this.firstReader,
  });

  /// Creates a copy of this log with the given fields updated.
  ReadLog copyWith({
    List<String>? likeNames,
    List<Comment>? comments,
    bool? liked,
    bool? firstReader,
  }) {
    return ReadLog(
      uid: uid,
      name: name,
      likeNames: likeNames ?? this.likeNames,
      comments: comments ?? this.comments,
      liked: liked ?? this.liked,
      firstReader: firstReader ?? this.firstReader,
    );
  }

  /// Builds a [ReadLog] from Firestore including likes and comments.
  static Future<ReadLog> fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String currentUid,
    String? firstReaderUid,
  }) async {
    final data = doc.data() ?? <String, dynamic>{};
    final likesSnapshot = await doc.reference.collection('likes').get();
    final likeDocs = likesSnapshot.docs;
    final liked = likeDocs.any((d) => d.id == currentUid);
    final likeNames = likeDocs
        .map((d) => (d.data()['name'] ?? 'Unknown').toString())
        .toList();
    final commentsSnap = await doc.reference
        .collection('comments')
        .orderBy('timestamp')
        .get();
    final comments = commentsSnap.docs
        .map((d) => Comment.fromFirestore(d))
        .toList();
    final name = (data['name'] ?? doc.id).toString().split(' ').first;
    return ReadLog(
      uid: doc.id,
      name: name,
      likeNames: likeNames,
      comments: comments,
      liked: liked,
      firstReader: firstReaderUid != null && doc.id == firstReaderUid,
    );
  }

  /// Parses a [ReadLog] from JSON.
  factory ReadLog.fromJson(Map<String, dynamic> json) => ReadLog(
    uid: json['uid'] as String? ?? '',
    name: json['name'] as String? ?? '',
    likeNames: List<String>.from(json['likeNames'] as List? ?? []),
    comments: List<Comment>.from(json['comments'] as List? ?? []),
    liked: json['liked'] as bool? ?? false,
    firstReader: json['firstReader'] as bool? ?? false,
  );
}

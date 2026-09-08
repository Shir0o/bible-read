import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/milestone_announcer.dart';

/// Represents a single read log entry.
class ReadLog {
  /// UID of the user who read.
  final String uid;

  /// Display name of the reader.
  final String name;

  /// Names of users who liked this entry.
  final List<String> likeNames;

  /// Whether the current user has liked this entry.
  final bool liked;

  /// The reader's shared Reflection text for this day, when they opted in
  /// (#807). Copied onto this entry by ReflectionService — the private
  /// Reflection document stays owner-only. Null when nothing is shared.
  final String? sharedReflection;

  /// Time when the user read.
  final DateTime? timestamp;

  /// A read-through this reader finished today, when they finished one.
  final FeedMilestone? milestone;

  const ReadLog({
    required this.uid,
    required this.name,
    required this.likeNames,
    required this.liked,
    this.sharedReflection,
    this.timestamp,
    this.milestone,
  });

  ReadLog copyWith({
    List<String>? likeNames,
    bool? liked,
    DateTime? timestamp,
    FeedMilestone? milestone,
    String? sharedReflection,
    bool clearSharedReflection = false,
  }) {
    return ReadLog(
      uid: uid,
      name: name,
      likeNames: likeNames ?? this.likeNames,
      liked: liked ?? this.liked,
      timestamp: timestamp ?? this.timestamp,
      milestone: milestone ?? this.milestone,
      sharedReflection: clearSharedReflection
          ? null
          : (sharedReflection ?? this.sharedReflection),
    );
  }

  /// Builds a [ReadLog] from Firestore including likes.
  static Future<ReadLog> fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String currentUid,
  }) async {
    final data = doc.data() ?? <String, dynamic>{};

    final likesSnap = await doc.reference.collection('likes').get();
    final liked = likesSnap.docs.any((d) => d.id == currentUid);
    final likeNames = likesSnap.docs
        .map((d) => (d.data()['name'] ?? 'Unknown').toString())
        .toList();
    final name = (data['name'] ?? doc.id).toString().split(' ').first;
    return ReadLog(
      uid: doc.id,
      name: name,
      likeNames: likeNames,
      liked: liked,
      sharedReflection:
          (data['sharedReflection'] as String?)?.trim().isEmpty ?? true
              ? null
              : data['sharedReflection'] as String?,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
      milestone: FeedMilestone.fromMap(data['milestone']),
    );
  }

  /// Parses a [ReadLog] from JSON.
  factory ReadLog.fromJson(Map<String, dynamic> json) => ReadLog(
        uid: json['uid'] as String? ?? '',
        name: json['name'] as String? ?? '',
        likeNames: List<String>.from(json['likeNames'] as List? ?? []),
        liked: json['liked'] as bool? ?? false,
        sharedReflection: json['sharedReflection'] as String?,
        timestamp: json['timestamp'] != null
            ? (json['timestamp'] is Timestamp
                ? (json['timestamp'] as Timestamp).toDate()
                : DateTime.tryParse(json['timestamp'].toString()))
            : null,
      );

  /// Converts this log to JSON.
  Map<String, dynamic> toJson() => {
        'uid': uid,
        'name': name,
        'likeNames': likeNames,
        'liked': liked,
        if (sharedReflection != null) 'sharedReflection': sharedReflection,
        'timestamp': timestamp?.toIso8601String(),
      };
}

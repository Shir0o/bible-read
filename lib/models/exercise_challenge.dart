import 'package:cloud_firestore/cloud_firestore.dart';

/// Type of target evaluated for an exercise challenge's daily goal.
enum ExerciseTargetType {
  /// The recorded amount must be greater than or equal to the goal.
  atLeast,

  /// The recorded amount must be less than or equal to the goal.
  atMost,

  /// The recorded amount must match the goal exactly.
  exactly,
}

/// Definition of a user-created exercise challenge.
class ExerciseChallenge {
  /// Firestore document identifier.
  final String id;

  /// UID of the user that owns the challenge.
  final String uid;

  /// Display name of the challenge.
  final String name;

  /// Unit label for progress entries (for example `minutes`).
  final String unit;

  /// Daily goal that determines whether the target is met.
  final double dailyGoal;

  /// Target evaluation applied to [dailyGoal].
  final ExerciseTargetType targetType;

  /// Optional overall target that tracks lifetime progress.
  final double? totalTarget;

  /// Optional categories used to group challenges in the UI.
  final List<String> categories;

  /// Whether the challenge has been archived by the user.
  final bool archived;

  /// Timestamp when the challenge was created.
  final DateTime? createdAt;

  /// Timestamp when the challenge was last updated.
  final DateTime? updatedAt;

  /// Creates an [ExerciseChallenge].
  ExerciseChallenge({
    required this.id,
    required this.uid,
    required this.name,
    required this.unit,
    required this.dailyGoal,
    this.targetType = ExerciseTargetType.atLeast,
    this.totalTarget,
    List<String>? categories,
    this.archived = false,
    this.createdAt,
    this.updatedAt,
  }) : categories = List.unmodifiable(categories ?? <String>[]);

  /// Reads a challenge from Firestore.
  factory ExerciseChallenge.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return ExerciseChallenge(
      id: doc.id,
      uid: data['uid'] as String? ?? '',
      name: data['name'] as String? ?? '',
      unit: data['unit'] as String? ?? '',
      dailyGoal: _asDouble(data['dailyGoal']),
      targetType: _parseTargetType(data['targetType']),
      totalTarget: data.containsKey('totalTarget')
          ? _asDouble(data['totalTarget'])
          : null,
      categories: _parseCategories(data['categories']),
      archived: data['archived'] as bool? ?? false,
      createdAt: _parseDate(data['createdAt']),
      updatedAt: _parseDate(data['updatedAt']),
    );
  }

  /// Serializes this challenge for Firestore writes.
  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'name': name,
      'unit': unit,
      'dailyGoal': dailyGoal,
      'targetType': targetType.name,
      if (totalTarget != null) 'totalTarget': totalTarget,
      'categories': categories,
      'archived': archived,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  /// Creates a copy of this challenge with updated fields.
  ExerciseChallenge copyWith({
    String? id,
    String? uid,
    String? name,
    String? unit,
    double? dailyGoal,
    ExerciseTargetType? targetType,
    double? totalTarget = _noTotalTarget,
    List<String>? categories,
    bool? archived,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final resolvedTotalTarget = identical(totalTarget, _noTotalTarget)
        ? this.totalTarget
        : totalTarget;
    return ExerciseChallenge(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      dailyGoal: dailyGoal ?? this.dailyGoal,
      targetType: targetType ?? this.targetType,
      totalTarget: resolvedTotalTarget,
      categories: categories ?? this.categories,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static const Object _noTotalTarget = Object();

  static double _asDouble(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0;
    }
    return 0;
  }

  static ExerciseTargetType _parseTargetType(Object? value) {
    if (value is String) {
      return ExerciseTargetType.values.firstWhere(
        (type) => type.name == value,
        orElse: () => ExerciseTargetType.atLeast,
      );
    }
    return ExerciseTargetType.atLeast;
  }

  static List<String> _parseCategories(Object? value) {
    if (value is List) {
      return value.whereType<String>().toList(growable: false);
    }
    return const <String>[];
  }

  static DateTime? _parseDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.round());
    }
    return null;
  }
}

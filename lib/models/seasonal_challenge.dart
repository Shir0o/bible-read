import 'package:cloud_firestore/cloud_firestore.dart';

import 'seasonal_reward.dart';

/// Definition of a seasonal challenge displayed to users.
class SeasonalChallenge {
  /// Document identifier of the challenge.
  final String id;

  /// Identifier of the season that owns this challenge.
  final String seasonId;

  /// Short name of the challenge.
  final String title;

  /// Longer description explaining the goal.
  final String description;

  /// Metric tracked for this challenge (for example `readings`).
  final String metric;

  /// Total amount required to complete the challenge.
  final int goal;

  /// Optional maximum amount that can be earned in a single day.
  final int dailyCap;

  /// Indicates whether the challenge can be repeated after completion.
  final bool repeatable;

  /// Reward information displayed when claiming.
  final SeasonalReward? reward;

  /// Creates a [SeasonalChallenge].
  const SeasonalChallenge({
    required this.id,
    required this.seasonId,
    required this.title,
    required this.description,
    required this.metric,
    required this.goal,
    this.dailyCap = 0,
    this.repeatable = false,
    this.reward,
  });

  /// Reads a [SeasonalChallenge] from Firestore.
  factory SeasonalChallenge.fromFirestore(
    String seasonId,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final rewardData = data['reward'];
    return SeasonalChallenge(
      id: doc.id,
      seasonId: data['seasonId'] as String? ?? seasonId,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      metric: data['metric'] as String? ?? '',
      goal: _asInt(data['goal']),
      dailyCap: _asInt(data['dailyCap']),
      repeatable: data['repeatable'] as bool? ?? false,
      reward: rewardData is Map<String, dynamic>
          ? SeasonalReward.fromMap(rewardData)
          : null,
    );
  }

  /// Serializes this challenge for Firestore writes.
  Map<String, dynamic> toFirestore() => {
    'seasonId': seasonId,
    'title': title,
    'description': description,
    'metric': metric,
    'goal': goal,
    'dailyCap': dailyCap,
    'repeatable': repeatable,
    if (reward != null) 'reward': reward!.toFirestore(),
  };

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}

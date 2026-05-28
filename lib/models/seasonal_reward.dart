import 'package:cloud_firestore/cloud_firestore.dart';

/// Metadata describing a reward granted for seasonal challenges.
class SeasonalReward {
  /// Firestore document id of the reward.
  final String id;

  /// Type identifier used by the client to determine reward handling.
  final String type;

  /// Display name of the reward.
  final String title;

  /// Optional description displayed in the UI.
  final String description;

  /// Optional image or icon representing the reward.
  final String iconUrl;

  /// Numeric amount associated with the reward (such as points).
  final int amount;

  /// Creates a [SeasonalReward].
  const SeasonalReward({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.amount,
    this.iconUrl = '',
  });

  /// Reads a [SeasonalReward] from a Firestore document.
  factory SeasonalReward.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return SeasonalReward(
      id: doc.id,
      type: data['type'] as String? ?? '',
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      iconUrl: data['iconUrl'] as String? ?? '',
      amount: _asInt(data['amount']),
    );
  }

  /// Reads a [SeasonalReward] from a nested map.
  factory SeasonalReward.fromMap(Map<String, dynamic>? data, {String id = ''}) {
    final values = data ?? <String, dynamic>{};
    return SeasonalReward(
      id: id.isEmpty ? values['id'] as String? ?? '' : id,
      type: values['type'] as String? ?? '',
      title: values['title'] as String? ?? '',
      description: values['description'] as String? ?? '',
      iconUrl: values['iconUrl'] as String? ?? '',
      amount: _asInt(values['amount']),
    );
  }

  /// Serializes the reward for Firestore writes.
  Map<String, dynamic> toFirestore() => {
    if (id.isNotEmpty) 'id': id,
    'type': type,
    'title': title,
    'description': description,
    'iconUrl': iconUrl,
    'amount': amount,
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

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/notification_preferences.dart';

/// Service for reading and updating notification preferences.
class NotificationPreferencesService {
  /// Firestore instance.
  final FirebaseFirestore firestore;

  final Map<String, NotificationPreferences> _cache = {};

  /// Creates a [NotificationPreferencesService].
  NotificationPreferencesService({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  /// Fetches preferences for the user with [uid]. Results are cached.
  Future<NotificationPreferences> fetchPreferences(String uid) async {
    final cached = _cache[uid];
    if (cached != null) return cached;
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('notificationPrefs')
        .get();
    final data = <String, dynamic>{};
    for (final doc in snap.docs) {
      final enabled = doc.data()['enabled'];
      data[doc.id] = enabled is bool ? enabled : true;
    }
    final prefs = NotificationPreferences.fromFirestore(data);
    _cache[uid] = prefs;
    return prefs;
  }

  /// Updates the preference [type] for [uid].
  Future<void> updatePreference(
      String uid, NotificationType type, bool enabled) async {
    await firestore
        .collection('users')
        .doc(uid)
        .collection('notificationPrefs')
        .doc(type.name)
        .set({'enabled': enabled});
    final current = _cache[uid] ?? NotificationPreferences();
    _cache[uid] = NotificationPreferences(values: {
      ...current.values,
      type: enabled,
    });
  }
}

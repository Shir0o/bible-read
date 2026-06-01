import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/notification_preferences.dart';

/// Service for reading and updating notification preferences.
class NotificationPreferencesService {
  /// Firestore instance.
  final FirebaseFirestore firestore;

  final Map<String, NotificationPreferences> _cache = {};
  final Map<String, bool> _vibrationCache = {};

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
      try {
        // Ignore documents that do not map to a [NotificationType].
        NotificationType.values.byName(doc.id);
      } catch (_) {
        continue;
      }
      final enabled = doc.data()['enabled'];
      data[doc.id] = enabled is bool ? enabled : true;
    }
    final prefs = NotificationPreferences.fromFirestore(data);
    _cache[uid] = prefs;
    return prefs;
  }

  /// Fetches whether vibration is enabled for the user with [uid].
  /// Results are cached.
  Future<bool> fetchVibrationEnabled(String uid) async {
    final cached = _vibrationCache[uid];
    if (cached != null) return cached;
    final doc = await firestore
        .collection('users')
        .doc(uid)
        .collection('notificationPrefs')
        .doc('vibration')
        .get();
    final enabled = doc.data()?['enabled'];
    final value = enabled is bool ? enabled : true;
    _vibrationCache[uid] = value;
    return value;
  }

  /// Updates the preference [type] for [uid].
  Future<void> updatePreference(
    String uid,
    NotificationType type,
    bool enabled,
  ) async {
    await firestore
        .collection('users')
        .doc(uid)
        .collection('notificationPrefs')
        .doc(type.name)
        .set({'enabled': enabled});
    final currentValues = _cache[uid]?.values ?? {};
    // Ensure the new preference is reflected in the cached copy.
    _cache[uid] = NotificationPreferences(
      values: {...currentValues, type: enabled},
    );
  }

  /// Updates the vibration preference for [uid].
  Future<void> updateVibrationEnabled(String uid, bool enabled) async {
    await firestore
        .collection('users')
        .doc(uid)
        .collection('notificationPrefs')
        .doc('vibration')
        .set({'enabled': enabled});
    _vibrationCache[uid] = enabled;
  }
}

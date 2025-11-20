import 'package:cloud_firestore/cloud_firestore.dart';

import 'error_logger.dart';

/// Service for reading and updating email preferences stored on the user doc.
class EmailPreferencesService {
  /// Firestore instance.
  final FirebaseFirestore firestore;

  /// Creates an [EmailPreferencesService].
  EmailPreferencesService({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  /// Fetches whether the monthly summary email is enabled for [uid]. Defaults
  /// to true when the preference is missing and persists the default.
  Future<bool> fetchMonthlySummaryEnabled(String uid) async {
    const defaultValue = true;
    try {
      final doc = await firestore.collection('users').doc(uid).get();
      final data = doc.data();
      final emailPrefs = data?['emailPrefs'];
      final stored = emailPrefs is Map<String, dynamic>
          ? emailPrefs['monthlySummary']
          : null;

      if (stored is bool) {
        return stored;
      }

      await firestore.collection('users').doc(uid).set({
        'emailPrefs': {'monthlySummary': defaultValue},
      }, SetOptions(merge: true));

      return defaultValue;
    } catch (error, stackTrace) {
      await ErrorLogger.log(error, stackTrace);
      return defaultValue;
    }
  }

  /// Updates the monthly summary email preference for [uid].
  Future<void> updateMonthlySummaryEnabled(String uid, bool enabled) async {
    await firestore.collection('users').doc(uid).set({
      'emailPrefs': {'monthlySummary': enabled},
    }, SetOptions(merge: true));
  }
}

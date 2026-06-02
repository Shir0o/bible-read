import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_preferences.dart';

/// Service for managing general user preferences.
class UserPreferencesService {
  /// Firestore instance.
  final FirebaseFirestore firestore;

  /// Creates a [UserPreferencesService].
  UserPreferencesService({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  /// Fetches the [UserPreferences] for a given user.
  Future<UserPreferences> fetchPreferences(String uid) async {
    final doc = await firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('general')
        .get();

    return UserPreferences.fromFirestore(doc.data());
  }

  /// Returns a stream of [UserPreferences] for a given user.
  Stream<UserPreferences> streamPreferences(String uid) {
    return firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('general')
        .snapshots()
        .map((doc) => UserPreferences.fromFirestore(doc.data()));
  }

  /// Updates the user's preferences.
  Future<void> updatePreferences(String uid, UserPreferences prefs) async {
    await firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('general')
        .set(prefs.toFirestore(), SetOptions(merge: true));
  }
}

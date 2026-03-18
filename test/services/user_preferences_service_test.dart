import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:bible_read/models/user_preferences.dart';
import 'package:bible_read/services/user_preferences_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late UserPreferencesService service;
  const uid = 'test-user';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = UserPreferencesService(firestore: firestore);
  });

  test('fetchPreferences returns default values if no document exists', () async {
    final prefs = await service.fetchPreferences(uid);
    expect(prefs.autoMarkPlanRead, isFalse);
  });

  test('updatePreferences creates document and fetchPreferences returns it', () async {
    const newPrefs = UserPreferences(
      autoMarkPlanRead: true,
    );

    await service.updatePreferences(uid, newPrefs);

    final fetched = await service.fetchPreferences(uid);
    expect(fetched.autoMarkPlanRead, isTrue);
  });
}

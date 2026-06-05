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

  test(
    'fetchPreferences returns default values if no document exists',
    () async {
      final prefs = await service.fetchPreferences(uid);
      expect(prefs.autoMarkPlanRead, isFalse);
      expect(prefs.syncPromptAnswered, isFalse);
    },
  );

  test(
    'updatePreferences creates document and fetchPreferences returns it',
    () async {
      const newPrefs =
          UserPreferences(autoMarkPlanRead: true, syncPromptAnswered: true);

      await service.updatePreferences(uid, newPrefs);

      final fetched = await service.fetchPreferences(uid);
      expect(fetched.autoMarkPlanRead, isTrue);
      expect(fetched.syncPromptAnswered, isTrue);
    },
  );

  test('syncPromptAnswered round-trips independently of autoMarkPlanRead',
      () async {
    // Answered but kept separate: prompt should not reappear, plan reading
    // does not count as showing up.
    await service.updatePreferences(
      uid,
      const UserPreferences(autoMarkPlanRead: false, syncPromptAnswered: true),
    );

    final fetched = await service.fetchPreferences(uid);
    expect(fetched.autoMarkPlanRead, isFalse);
    expect(fetched.syncPromptAnswered, isTrue);
  });
}

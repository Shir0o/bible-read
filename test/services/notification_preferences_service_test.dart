import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bible_read/models/notification_preferences.dart';
import 'package:bible_read/services/notification_preferences_service.dart';

class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class _MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

void main() {
  group('NotificationPreferencesService', () {
    late FakeFirebaseFirestore firestore;
    late NotificationPreferencesService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = NotificationPreferencesService(firestore: firestore);
    });

    test('fetchPreferences defaults missing types to true', () async {
      final prefs = await service.fetchPreferences('u1');
      for (final t in NotificationType.values) {
        expect(prefs[t], isTrue);
      }
    });

    test(
        'fetchPreferences returns true for dailyReminder when no document exists',
        () async {
      final prefs = await service.fetchPreferences('u1');
      expect(prefs[NotificationType.dailyReminder], isTrue);
    });

    test('updatePreference writes document and updates cache', () async {
      await service.updatePreference(
          'u1', NotificationType.dailyReminder, false);
      final doc = await firestore
          .collection('users')
          .doc('u1')
          .collection('notificationPrefs')
          .doc('dailyReminder')
          .get();
      expect(doc.exists, isTrue);
      expect(doc.data()?['enabled'], false);

      final prefs = await service.fetchPreferences('u1');
      expect(prefs[NotificationType.dailyReminder], isFalse);
    });

    test('fetchPreferences caches results', () async {
      final firestore = _MockFirebaseFirestore();
      final users = _MockCollectionReference();
      final userDoc = _MockDocumentReference();
      final prefsCol = _MockCollectionReference();
      final snap = _MockQuerySnapshot();

      var reads = 0;

      when(() => firestore.collection('users')).thenReturn(users);
      when(() => users.doc('u1')).thenReturn(userDoc);
      when(() => userDoc.collection('notificationPrefs'))
          .thenReturn(prefsCol);
      when(() => prefsCol.get()).thenAnswer((_) async {
        reads++;
        when(() => snap.docs)
            .thenReturn(<QueryDocumentSnapshot<Map<String, dynamic>>>[]);
        return snap;
      });

      final service = NotificationPreferencesService(firestore: firestore);

      await service.fetchPreferences('u1');
      await service.fetchPreferences('u1');

      expect(reads, 1);
    });

    test('non-boolean enabled values default to true', () async {
      await firestore
          .collection('users')
          .doc('u1')
          .collection('notificationPrefs')
          .doc('dailyReminder')
          .set({'enabled': 'yes'});

      final prefs = await service.fetchPreferences('u1');

      expect(prefs[NotificationType.dailyReminder], isTrue);
    });
  });
}

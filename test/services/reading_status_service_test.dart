// ignore_for_file: subtype_of_sealed_class

import 'package:bible_read/services/reading_status_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReadingStatusService', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late ReadingStatusService service;
    late MockUser user;

    setUp(() {
      user = MockUser(
        uid: 'user1',
        email: 'user1@test.com',
        displayName: 'User One',
      );
      auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      firestore = FakeFirebaseFirestore();
      service = ReadingStatusService(firestore: firestore, auth: auth);
    });

    test('fetchStatus creates user document when missing', () async {
      await service.fetchStatus();

      final doc = await firestore.collection('users').doc(user.uid).get();
      expect(doc.exists, isTrue);
      expect(doc.data()?['email'], user.email?.toLowerCase());
    });

    test('fetchStatus backfills partial week and month data', () async {
      final userDoc = firestore.collection('users').doc(user.uid);
      await userDoc.set({'name': 'User One', 'email': user.email});

      final now = DateTime.now();
      String formatDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      await userDoc.collection('summary').doc('data').set({
        'pastWeekReadDates': [formatDate(now)],
        'pastMonthReadDates': [formatDate(now)],
      });

      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      for (int i = 0; i < 30; i++) {
        final date = now.subtract(Duration(days: i));
        await userDoc
            .collection('reading')
            .doc(formatDate(date))
            .set({'read': true});
      }

      final status = await service.fetchStatus();
      expect(status.pastWeek.length, 7);
      final expectedWeekTrue = DateTime.now().weekday % 7 + 1;
      expect(status.pastWeek.where((e) => e).length, expectedWeekTrue);

      expect(status.pastMonth.length, daysInMonth);
      final expectedMonthTrue = DateTime.now().day;
      expect(status.pastMonth.where((e) => e).length, expectedMonthTrue);
    });
  });
}

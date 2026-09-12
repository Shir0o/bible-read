// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:bible_read/services/reading_status_service.dart';
import 'package:bible_read/services/reflection_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

Future<T> nextWhere<T>(Stream<T> stream, bool Function(T value) predicate) {
  final completer = Completer<T>();
  late StreamSubscription<T> subscription;
  subscription = stream.listen((value) {
    if (predicate(value) && completer.isCompleted == false) {
      completer.complete(value);
      subscription.cancel();
    }
  });
  return completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReadingStatusService streams', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late ReadingStatusService service;
    late MockUser user;
    late DateTime fixedNow;

    setUp(() {
      user = MockUser(
        uid: 'user1',
        email: 'user1@test.com',
        displayName: 'User One',
      );
      auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      firestore = FakeFirebaseFirestore();
      fixedNow = DateTime(2024, 7, 30);
      service = ReadingStatusService(
        firestore: firestore,
        auth: auth,
        nowProvider: () => fixedNow,
      );
    });

    test('watchStatus emits when today reading document changes', () async {
      final changed = nextWhere(
        service.watchStatus(),
        (status) => status.readToday,
      );

      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('reading')
          .doc('2024-07-30')
          .set({'read': true});

      final status = await changed.timeout(const Duration(seconds: 3));
      expect(status.readToday, isTrue);
    });

    test('watchStatus emits when the summary document changes', () async {
      final changed = nextWhere(
        service.watchStatus(),
        (status) => status.streak == 9,
      );

      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('summary')
          .doc('data')
          .set({'streak': 9});

      final status = await changed.timeout(const Duration(seconds: 3));
      expect(status.streak, 9);
    });

    test('watchStreak emits when the summary document changes', () async {
      final changed = nextWhere(service.watchStreak(user.uid), (s) => s == 7);

      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('summary')
          .doc('data')
          .set({'streak': 7});

      expect(await changed.timeout(const Duration(seconds: 3)), 7);
    });

    test('watchReadDatesForRange emits added reading days', () async {
      final changed = nextWhere(
        service.watchReadDatesForRange(
          user.uid,
          31,
          referenceDate: fixedNow,
        ),
        (dates) => dates.contains(DateTime(2024, 7, 30)),
      );

      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('reading')
          .doc('2024-07-30')
          .set({'read': true});

      final dates = await changed.timeout(const Duration(seconds: 3));
      expect(dates, contains(DateTime(2024, 7, 30)));
    });
  });

  group('ReflectionService stream', () {
    test('watchReflection emits saved text and deletion', () async {
      final firestore = FakeFirebaseFirestore();
      final service = ReflectionService(firestore: firestore);
      const uid = 'u1';
      const dateKey = '2024-07-30';

      final saved = nextWhere(
        service.watchReflection(uid, dateKey),
        (reflection) => reflection?.text == 'Live update',
      );

      await firestore
          .collection('users')
          .doc(uid)
          .collection('reflections')
          .doc(dateKey)
          .set({'text': 'Live update', 'shared': false});

      expect(
        (await saved.timeout(const Duration(seconds: 3)))?.text,
        'Live update',
      );

      final deleted = nextWhere(
        service.watchReflection(uid, dateKey),
        (reflection) => reflection == null,
      );
      await firestore
          .collection('users')
          .doc(uid)
          .collection('reflections')
          .doc(dateKey)
          .delete();
      expect(await deleted.timeout(const Duration(seconds: 3)), isNull);
    });
  });
}

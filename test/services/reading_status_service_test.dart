// ignore_for_file: subtype_of_sealed_class

import 'package:bible_read/services/error_logger.dart';
import 'package:bible_read/services/reading_status_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseCrashlytics extends Mock implements FirebaseCrashlytics {}

class ThrowingFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    if (path == 'users') {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        message: 'forced failure',
      );
    }
    return super.collection(path);
  }
}

class _FakeFirebasePlatform extends FirebasePlatform {
  _FakeFirebasePlatform() {
    _apps.add(_FakeFirebaseApp(defaultFirebaseAppName, _defaultOptions));
  }

  final List<FirebaseAppPlatform> _apps = [];

  @override
  List<FirebaseAppPlatform> get apps => List.unmodifiable(_apps);

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) {
    return _apps.firstWhere((a) => a.name == name);
  }

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    final app = _FakeFirebaseApp(
        name ?? defaultFirebaseAppName, options ?? _defaultOptions);
    _apps.removeWhere((existing) => existing.name == app.name);
    _apps.add(app);
    return app;
  }
}

class _FakeFirebaseApp extends FirebaseAppPlatform {
  _FakeFirebaseApp(super.name, super.options);

  bool _automaticDataCollectionEnabled = true;

  @override
  bool get isAutomaticDataCollectionEnabled => _automaticDataCollectionEnabled;

  @override
  Future<void> delete() async {}

  @override
  Future<void> setAutomaticDataCollectionEnabled(bool enabled) async {
    _automaticDataCollectionEnabled = enabled;
  }

  @override
  Future<void> setAutomaticResourceManagementEnabled(bool enabled) async {}
}

const FirebaseOptions _defaultOptions = FirebaseOptions(
  apiKey: 'test',
  appId: '1:123:test:android',
  messagingSenderId: '123',
  projectId: 'test',
);

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

    test('updateSummary computes streak, longest streak, and totals', () async {
      final userDoc = firestore.collection('users').doc(user.uid);
      await userDoc.set({'email': user.email});

      String formatDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final today = DateTime.now();
      final streakOffsets = [0, 1, 2];
      final longestOffsets = [5, 6, 7, 8, 9, 10];

      for (final offset in [...streakOffsets, ...longestOffsets]) {
        final date = today.subtract(Duration(days: offset));
        await userDoc
            .collection('reading')
            .doc(formatDate(date))
            .set({'read': true});
      }

      final stats = await service.updateSummary();
      expect(stats.streak, streakOffsets.length);
      expect(stats.totalReadDays, streakOffsets.length + longestOffsets.length);

      final summaryDoc = await userDoc.collection('summary').doc('data').get();
      expect(summaryDoc.exists, isTrue);
      expect(summaryDoc.data()?['streak'], streakOffsets.length);
      expect(summaryDoc.data()?['longestStreak'], longestOffsets.length);
      expect(summaryDoc.data()?['totalReadDays'],
          streakOffsets.length + longestOffsets.length);
    });

    test(
        'updateSummary backfills data from read_logs when reading docs missing',
        () async {
      final date = DateTime.now();
      String formatDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      await firestore
          .collection('read_logs')
          .doc(formatDate(date))
          .collection('entries')
          .doc(user.uid)
          .set({'read': true});

      final stats = await service.updateSummary();
      expect(stats.streak, 1);
      expect(stats.totalReadDays, 1);

      final summaryDoc = await firestore
          .collection('users')
          .doc(user.uid)
          .collection('summary')
          .doc('data')
          .get();
      expect(summaryDoc.exists, isTrue);
      final data = summaryDoc.data()!;
      expect(data['streak'], 1);
      expect(data['totalReadDays'], 1);
      expect(data['pastWeekReadDates'], contains(formatDate(date)));
    });

    test('updateSummary logs and rethrows when Firestore operations fail',
        () async {
      final throwingFirestore = ThrowingFirestore();
      service = ReadingStatusService(firestore: throwingFirestore, auth: auth);

      final originalDelegate = Firebase.delegatePackingProperty;
      Firebase.delegatePackingProperty = _FakeFirebasePlatform();
      final crashlytics = MockFirebaseCrashlytics();
      FirebaseCrashlytics? originalCrashlytics;
      try {
        originalCrashlytics = ErrorLogger.crashlytics;
      } catch (_) {
        originalCrashlytics = null;
      }
      ErrorLogger.crashlytics = crashlytics;
      addTearDown(() {
        Firebase.delegatePackingProperty = originalDelegate;
        if (originalCrashlytics != null) {
          ErrorLogger.crashlytics = originalCrashlytics;
        }
      });

      when(() =>
              crashlytics.recordError(any(), any(), fatal: any(named: 'fatal')))
          .thenAnswer((_) async {});

      final future = service.updateSummary();
      await expectLater(
        future,
        throwsA(isA<FirebaseException>()
            .having((e) => e.message, 'message', contains('forced failure'))),
      );

      verify(() => crashlytics.recordError(
            any(that: isA<FirebaseException>()),
            any(),
            fatal: false,
          )).called(1);
    });
  });
}

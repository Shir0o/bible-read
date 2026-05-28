// ignore_for_file: subtype_of_sealed_class

import 'dart:math' as math;

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
      name ?? defaultFirebaseAppName,
      options ?? _defaultOptions,
    );
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

    test('fetchStatus creates user document when missing', () async {
      final status = await service.fetchStatus();

      final doc = await firestore.collection('users').doc(user.uid).get();
      expect(doc.exists, isTrue);
      expect(doc.data()?['email'], user.email?.toLowerCase());
      expect(status.graceCreditsAvailable, 0);
      final today = fixedNow;
      expect(
        status.graceCreditsMonth,
        '${today.year}-${today.month.toString().padLeft(2, '0')}',
      );
    });

    test('fetchStatus backfills partial week and month data', () async {
      final userDoc = firestore.collection('users').doc(user.uid);
      await userDoc.set({'name': 'User One', 'email': user.email});

      final now = fixedNow;
      String formatDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      await userDoc.collection('summary').doc('data').set({
        'pastWeekReadDates': [formatDate(now)],
        'pastMonthReadDates': [formatDate(now)],
        'graceCreditsAvailable': 5,
        'graceCreditsMonth':
            '${now.year}-${now.month.toString().padLeft(2, '0')}',
      });

      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      for (int i = 0; i < 30; i++) {
        final date = now.subtract(Duration(days: i));
        await userDoc.collection('reading').doc(formatDate(date)).set({
          'read': true,
        });
      }

      final status = await service.fetchStatus();
      expect(status.pastWeek.length, 7);
      final expectedWeekTrue = fixedNow.weekday % 7 + 1;
      expect(status.pastWeek.where((e) => e).length, expectedWeekTrue);

      expect(status.pastMonth.length, daysInMonth);
      final expectedMonthTrue = math.min(fixedNow.day, 30);
      expect(status.pastMonth.where((e) => e).length, expectedMonthTrue);
      expect(status.graceCreditsAvailable, 5);
    });

    test('updateSummary computes streak, longest streak, and totals', () async {
      final userDoc = firestore.collection('users').doc(user.uid);
      await userDoc.set({'email': user.email});

      String formatDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final today = fixedNow;
      final streakOffsets = [0, 1, 2];
      final longestOffsets = [5, 6, 7, 8, 9, 10];

      for (final offset in [...streakOffsets, ...longestOffsets]) {
        final date = today.subtract(Duration(days: offset));
        await userDoc.collection('reading').doc(formatDate(date)).set({
          'read': true,
        });
      }

      final stats = await service.updateSummary();
      final expectedStreak = longestOffsets.last + 1;
      expect(stats.streak, expectedStreak);
      final expectedReadDays = streakOffsets.length + longestOffsets.length;
      expect(stats.totalReadDays, expectedReadDays);
      expect(stats.coveredDate, today);
      expect(stats.coveredViaGrace, isFalse);
      expect(
        stats.graceCreditsMonth,
        '${today.year}-${today.month.toString().padLeft(2, '0')}',
      );

      final summaryDoc = await userDoc.collection('summary').doc('data').get();
      expect(summaryDoc.exists, isTrue);
      expect(summaryDoc.data()?['streak'], expectedStreak);
      // Longest streak now consistently includes days covered by grace credits.
      expect(summaryDoc.data()?['longestStreak'], expectedStreak);
      expect(summaryDoc.data()?['totalReadDays'], expectedReadDays);
    });

    test(
      'updateSummary backfills data from read_logs when reading docs missing',
      () async {
        final date = fixedNow;
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
        expect(stats.graceCreditsAvailable, 2);
        expect(stats.graceCreditsUsed, 0);

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
        expect(data['graceCreditsAvailable'], 2);
        expect(data['graceCreditsUsed'], 0);
      },
    );

    test('updateSummary uses grace credits to preserve streak', () async {
      final userDoc = firestore.collection('users').doc(user.uid);
      await userDoc.set({'email': user.email});

      String formatDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final today = fixedNow;
      for (final offset in [0, 2, 3]) {
        final date = today.subtract(Duration(days: offset));
        await userDoc.collection('reading').doc(formatDate(date)).set({
          'read': true,
        });
      }

      final stats = await service.updateSummary();
      expect(stats.streak, 4);
      expect(stats.graceCreditsUsed, 1);
      expect(stats.graceCreditsAvailable, 1);
      expect(stats.coveredViaGrace, isFalse);

      final summaryDoc = await userDoc.collection('summary').doc('data').get();
      final data = summaryDoc.data()!;
      expect(data['streak'], 4);
      expect(data['graceCreditsUsed'], 1);
      expect(data['graceCreditsAvailable'], 1);
    });

    test(
      'updateSummary reports when today was covered by a grace credit',
      () async {
        final userDoc = firestore.collection('users').doc(user.uid);
        await userDoc.set({'email': user.email});

        String formatDate(DateTime d) =>
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

        final today = fixedNow;
        final yesterday = today.subtract(const Duration(days: 1));
        await userDoc.collection('reading').doc(formatDate(yesterday)).set({
          'read': true,
        });

        final stats = await service.updateSummary();
        expect(stats.streak, 2);
        expect(stats.coveredDate, today);
        expect(stats.coveredViaGrace, isTrue);
      },
    );

    test(
      'updateSummary leaves new month credits untouched when streak already reset',
      () async {
        final userDoc = firestore.collection('users').doc(user.uid);
        await userDoc.set({'email': user.email});

        String formatDate(DateTime d) =>
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

        fixedNow = DateTime(2024, 7, 2);

        // User read on the first two days of June and then missed enough days to
        // exhaust June's grace credits, resetting the streak before July.
        for (final date in [DateTime(2024, 6, 1), DateTime(2024, 6, 2)]) {
          await userDoc.collection('reading').doc(formatDate(date)).set({
            'read': true,
          });
        }

        final stats = await service.updateSummary();
        expect(stats.graceCreditsMonth, '2024-07');
        expect(stats.streak, 0);
        expect(stats.graceCreditsUsed, 0);
        expect(stats.graceCreditsAvailable, 2);

        final summaryDoc = await userDoc
            .collection('summary')
            .doc('data')
            .get();
        final data = summaryDoc.data()!;
        expect(data['graceCreditsMonth'], '2024-07');
        expect(data['graceCreditsUsed'], 0);
        expect(data['graceCreditsAvailable'], 2);
      },
    );

    test('updateSummary breaks streak when credits exhausted', () async {
      final userDoc = firestore.collection('users').doc(user.uid);
      await userDoc.set({'email': user.email});

      String formatDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final today = fixedNow;
      for (final offset in [0, 4, 5]) {
        final date = today.subtract(Duration(days: offset));
        await userDoc.collection('reading').doc(formatDate(date)).set({
          'read': true,
        });
      }

      final stats = await service.updateSummary();
      expect(stats.streak, 1);
      expect(stats.graceCreditsUsed, 2);
      expect(stats.graceCreditsAvailable, 0);
      expect(stats.coveredViaGrace, isFalse);

      final summaryDoc = await userDoc.collection('summary').doc('data').get();
      final data = summaryDoc.data()!;
      expect(data['streak'], 1);
      expect(data['graceCreditsUsed'], 2);
      expect(data['graceCreditsAvailable'], 0);
    });

    test('updateSummary awards bonus credit after 15-day streak', () async {
      final userDoc = firestore.collection('users').doc(user.uid);
      await userDoc.set({'email': user.email});

      String formatDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final today = fixedNow;
      for (int i = 0; i < 15; i++) {
        final date = today.subtract(Duration(days: i));
        await userDoc.collection('reading').doc(formatDate(date)).set({
          'read': true,
        });
      }

      final stats = await service.updateSummary();
      expect(stats.streak, 15);
      expect(stats.graceCreditsUsed, 0);
      expect(stats.graceCreditsAvailable, 3);

      final summaryDoc = await userDoc.collection('summary').doc('data').get();
      final data = summaryDoc.data()!;
      expect(data['graceCreditsAvailable'], 3);
      expect(data['graceCreditsUsed'], 0);
    });

    test(
      'updateSummary does not forgive misses that occur before a credit is earned',
      () async {
        final fixedToday = DateTime(2024, 6, 30);
        service = ReadingStatusService(
          firestore: firestore,
          auth: auth,
          nowProvider: () => fixedToday,
        );

        final userDoc = firestore.collection('users').doc(user.uid);
        await userDoc.set({'email': user.email});

        String formatDate(DateTime d) =>
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final today = fixedToday;
        DateTime dayFor(int daysAgo) => today.subtract(Duration(days: daysAgo));

        Future<void> markRead(int daysAgo) async {
          final date = dayFor(daysAgo);
          await userDoc.collection('reading').doc(formatDate(date)).set({
            'read': true,
          });
        }

        final readDaysAgo = <int>[30, ...List.generate(27, (i) => 26 - i)];
        for (final daysAgo in readDaysAgo) {
          await markRead(daysAgo);
        }

        final monthKey =
            '${today.year}-${today.month.toString().padLeft(2, '0')}';
        final stats = await service.updateSummary();
        expect(stats.streak, 27);
        expect(stats.graceCreditsMonth, monthKey);
        expect(stats.graceCreditsUsed, 2);
        expect(stats.graceCreditsAvailable, 1);

        final summaryDoc = await userDoc
            .collection('summary')
            .doc('data')
            .get();
        expect(summaryDoc.data()?['graceCreditsUsed'], 2);
        expect(summaryDoc.data()?['graceCreditsAvailable'], 1);
      },
    );

    test('updateSummary spends earned credits on later misses', () async {
      final fixedToday = DateTime(2024, 6, 30);
      service = ReadingStatusService(
        firestore: firestore,
        auth: auth,
        nowProvider: () => fixedToday,
      );

      final userDoc = firestore.collection('users').doc(user.uid);
      await userDoc.set({'email': user.email});

      String formatDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final today = fixedToday;
      DateTime dayFor(int daysAgo) => today.subtract(Duration(days: daysAgo));

      Future<void> markRead(int daysAgo) async {
        final date = dayFor(daysAgo);
        await userDoc.collection('reading').doc(formatDate(date)).set({
          'read': true,
        });
      }

      final readDaysAgo = <int>[25, ...List.generate(22, (i) => 22 - i)];
      for (final daysAgo in readDaysAgo) {
        await markRead(daysAgo);
      }

      final monthKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}';
      final stats = await service.updateSummary();
      expect(stats.streak, 26);
      expect(stats.graceCreditsMonth, monthKey);
      expect(stats.graceCreditsUsed, 3);
      expect(stats.graceCreditsAvailable, 0);

      final summaryDoc = await userDoc.collection('summary').doc('data').get();
      expect(summaryDoc.data()?['graceCreditsUsed'], 3);
      expect(summaryDoc.data()?['graceCreditsAvailable'], 0);
    });

    test(
      'updateSummary logs and rethrows when Firestore operations fail',
      () async {
        final throwingFirestore = ThrowingFirestore();
        service = ReadingStatusService(
          firestore: throwingFirestore,
          auth: auth,
          nowProvider: () => fixedNow,
        );

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

        when(
          () =>
              crashlytics.recordError(any(), any(), fatal: any(named: 'fatal')),
        ).thenAnswer((_) async {});

        final future = service.updateSummary();
        await expectLater(
          future,
          throwsA(
            isA<FirebaseException>().having(
              (e) => e.message,
              'message',
              contains('forced failure'),
            ),
          ),
        );

        verify(
          () => crashlytics.recordError(
            any(that: isA<FirebaseException>()),
            any(),
            fatal: false,
          ),
        ).called(1);
      },
    );
  });
}

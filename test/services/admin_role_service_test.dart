import 'dart:collection';
import 'package:bible_read/services/admin_role_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingAdminRoleService extends AdminRoleService {
  _CountingAdminRoleService(
    Queue<bool> responses, {
    super.cacheDuration = const Duration(minutes: 5),
  })  : _responses = responses,
        super(auth: MockFirebaseAuth(), firestore: FakeFirebaseFirestore());

  final Queue<bool> _responses;
  int fetchCount = 0;

  @override
  Future<bool> fetchAdminRole() async {
    fetchCount++;
    return _responses.isNotEmpty ? _responses.removeFirst() : false;
  }
}

void main() {
  group('AdminRoleService caching', () {
    test('prewarm caches value and isAdmin returns cached result', () async {
      final service = _CountingAdminRoleService(ListQueue<bool>.from([true]));

      final result = await service.prewarm();

      expect(result, isTrue);
      expect(service.cachedAdminRole, isTrue);
      expect(service.hasValidCache, isTrue);

      final previousFetches = service.fetchCount;
      final secondCall = await service.isAdmin();

      expect(secondCall, isTrue);
      expect(service.fetchCount, previousFetches);
    });

    test(
      'stale cache returns quickly while refreshing in background',
      () async {
        final service = _CountingAdminRoleService(
          ListQueue<bool>.from([true]),
          cacheDuration: const Duration(milliseconds: 100),
        );

        service.primeCacheForTest(
          false,
          timestamp: DateTime.now().subtract(const Duration(seconds: 1)),
        );

        expect(service.hasValidCache, isFalse);
        final stopwatch = Stopwatch()..start();
        final result = await service.isAdmin();
        stopwatch.stop();

        expect(result, isFalse);
        expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 20)));

        final refreshFuture = service.refreshing;

        expect(refreshFuture, isNotNull);
        expect(await refreshFuture, isTrue);

        expect(service.fetchCount, 1);
        expect(service.cachedAdminRole, isTrue);
        expect(service.hasValidCache, isTrue);
      },
    );
  });
}

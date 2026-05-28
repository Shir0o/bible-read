import 'package:bible_read/services/data_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DataCacheService', () {
    late DataCacheService cache;

    setUp(() {
      cache = DataCacheService(defaultTtl: const Duration(seconds: 2));
    });

    test('getOrFetch calls fetcher on first access', () async {
      var callCount = 0;
      final result = await cache.getOrFetch<String>('key1', () async {
        callCount++;
        return 'value1';
      });

      expect(result, 'value1');
      expect(callCount, 1);
    });

    test(
      'getOrFetch returns cached value on second access within TTL',
      () async {
        var callCount = 0;
        Future<String> fetcher() async {
          callCount++;
          return 'value1';
        }

        await cache.getOrFetch<String>('key1', fetcher);
        final result = await cache.getOrFetch<String>('key1', fetcher);

        expect(result, 'value1');
        expect(callCount, 1, reason: 'fetcher should only be called once');
      },
    );

    test('getOrFetch re-fetches after TTL expires', () async {
      final shortCache = DataCacheService(
        defaultTtl: const Duration(milliseconds: 50),
      );
      var callCount = 0;

      Future<String> fetcher() async {
        callCount++;
        return 'value_$callCount';
      }

      final first = await shortCache.getOrFetch<String>('key1', fetcher);
      expect(first, 'value_1');

      // Wait for TTL to expire
      await Future.delayed(const Duration(milliseconds: 60));

      final second = await shortCache.getOrFetch<String>('key1', fetcher);
      expect(second, 'value_2');
      expect(callCount, 2);
    });

    test('invalidate forces re-fetch', () async {
      var callCount = 0;
      Future<String> fetcher() async {
        callCount++;
        return 'value_$callCount';
      }

      await cache.getOrFetch<String>('key1', fetcher);
      expect(callCount, 1);

      cache.invalidate('key1');

      final result = await cache.getOrFetch<String>('key1', fetcher);
      expect(result, 'value_2');
      expect(callCount, 2);
    });

    test('invalidatePrefix clears matching entries', () async {
      await cache.getOrFetch<String>('reading:u1', () async => 'status1');
      await cache.getOrFetch<String>('reading:u2', () async => 'status2');
      await cache.getOrFetch<String>('journey:u1', () async => 'progress1');

      expect(cache.length, 3);

      cache.invalidatePrefix('reading:');

      expect(cache.length, 1);
      expect(cache.peek<String>('reading:u1'), isNull);
      expect(cache.peek<String>('reading:u2'), isNull);
      expect(cache.peek<String>('journey:u1'), 'progress1');
    });

    test('clear removes all entries', () async {
      await cache.getOrFetch<String>('a', () async => '1');
      await cache.getOrFetch<String>('b', () async => '2');
      expect(cache.length, 2);

      cache.clear();
      expect(cache.length, 0);
    });

    test('peek returns null for missing key', () {
      expect(cache.peek<String>('nonexistent'), isNull);
    });

    test('peek returns cached value within TTL', () async {
      await cache.getOrFetch<String>('key1', () async => 'val');
      expect(cache.peek<String>('key1'), 'val');
    });

    test('peek returns null for expired entry', () async {
      final shortCache = DataCacheService(
        defaultTtl: const Duration(milliseconds: 50),
      );
      await shortCache.getOrFetch<String>('key1', () async => 'val');

      await Future.delayed(const Duration(milliseconds: 60));
      expect(shortCache.peek<String>('key1'), isNull);
    });

    test('put stores value directly', () {
      cache.put<String>('direct', 'stored');
      expect(cache.peek<String>('direct'), 'stored');
    });

    test('per-key TTL override works', () async {
      final result = await cache.getOrFetch<String>(
        'short_lived',
        () async => 'val',
        ttl: const Duration(milliseconds: 50),
      );
      expect(result, 'val');

      await Future.delayed(const Duration(milliseconds: 60));

      var callCount = 0;
      final result2 = await cache.getOrFetch<String>('short_lived', () async {
        callCount++;
        return 'val2';
      }, ttl: const Duration(milliseconds: 50));
      expect(result2, 'val2');
      expect(callCount, 1);
    });
  });
}

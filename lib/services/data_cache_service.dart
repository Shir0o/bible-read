/// A lightweight in-memory cache with time-based expiry and key invalidation.
///
/// Use [getOrFetch] to retrieve cached data or fetch it fresh if expired.
/// Call [invalidate] or [invalidatePrefix] after editing data to ensure
/// subsequent reads return fresh results.
class DataCacheService {
  /// Creates a [DataCacheService] with the given default TTL.
  DataCacheService({this.defaultTtl = const Duration(minutes: 5)});

  /// Default time-to-live for cached entries.
  final Duration defaultTtl;

  final Map<String, _CacheEntry<Object>> _entries = {};

  /// Returns cached data for [key] if fresh, otherwise calls [fetcher],
  /// caches the result, and returns it.
  Future<T> getOrFetch<T>(
    String key,
    Future<T> Function() fetcher, {
    Duration? ttl,
  }) async {
    final entry = _entries[key];
    final effectiveTtl = ttl ?? defaultTtl;
    if (entry != null && !entry.isExpired(effectiveTtl)) {
      return entry.value as T;
    }
    final value = await fetcher();
    _entries[key] = _CacheEntry<Object>(
      value: value as Object,
      cachedAt: DateTime.now(),
    );
    return value;
  }

  /// Returns the cached value for [key] without fetching, or `null` if
  /// the entry is missing or expired.
  T? peek<T>(String key, {Duration? ttl}) {
    final entry = _entries[key];
    if (entry == null || entry.isExpired(ttl ?? defaultTtl)) return null;
    return entry.value as T;
  }

  /// Stores [value] in the cache under [key].
  void put<T>(String key, T value) {
    _entries[key] = _CacheEntry<Object>(
      value: value as Object,
      cachedAt: DateTime.now(),
    );
  }

  /// Removes the entry for [key], forcing the next [getOrFetch] to call
  /// its fetcher.
  void invalidate(String key) {
    _entries.remove(key);
  }

  /// Removes all entries whose keys start with [prefix].
  void invalidatePrefix(String prefix) {
    _entries.removeWhere((key, _) => key.startsWith(prefix));
  }

  /// Removes all cached entries.
  void clear() {
    _entries.clear();
  }

  /// The number of entries currently in the cache (mainly for testing).
  int get length => _entries.length;
}

class _CacheEntry<T> {
  _CacheEntry({required this.value, required this.cachedAt});

  final T value;
  final DateTime cachedAt;

  bool isExpired(Duration ttl) => DateTime.now().difference(cachedAt) > ttl;
}

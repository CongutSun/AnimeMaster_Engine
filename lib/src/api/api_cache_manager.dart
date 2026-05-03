import 'dart:collection';

/// A single cache entry with a creation timestamp for TTL eviction.
class _CacheEntry<T> {
  final T value;
  final DateTime createdAt;
  const _CacheEntry(this.value, this.createdAt);
}

/// LRU + TTL cache that replaces the 16 ad‑hoc static [Map]s in BangumiApi.
///
/// Features:
/// - Max entry count (LRU eviction of oldest entries)
/// - Per‑key TTL (optional — omit for permanent‑until‑evicted behavior)
/// - Thread‑safe via single‑threaded Flutter usage
class ApiCacheManager<T> {
  ApiCacheManager({this.maxSize = 80, this.defaultTtl});

  final int maxSize;
  final Duration? defaultTtl;
  final LinkedHashMap<dynamic, _CacheEntry<T>> _store =
      LinkedHashMap<dynamic, _CacheEntry<T>>();

  T? get(dynamic key) {
    final _CacheEntry<T>? entry = _store[key];
    if (entry == null) return null;

    if (defaultTtl != null &&
        DateTime.now().difference(entry.createdAt) >= defaultTtl!) {
      _store.remove(key);
      return null;
    }

    // Move to end (most recently used).
    _store.remove(key);
    _store[key] = entry;
    return entry.value;
  }

  void set(dynamic key, T value) {
    _store.remove(key);
    _store[key] = _CacheEntry<T>(value, DateTime.now());
    _evictIfNeeded();
  }

  void remove(dynamic key) => _store.remove(key);

  void clear() => _store.clear();

  int get length => _store.length;

  void _evictIfNeeded() {
    while (_store.length > maxSize) {
      // LinkedHashMap preserves insertion order — first is oldest.
      _store.remove(_store.keys.first);
    }
  }
}

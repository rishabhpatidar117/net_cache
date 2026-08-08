import '../response/api_response.dart';

/// A single cached response plus when it expires.
class CacheEntry {
  final ApiResponse response;
  final DateTime expiresAt;

  CacheEntry({required this.response, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Storage backend for cached responses. [SmartApiClient] ships with
/// [MemoryCacheStore] (default — cleared on app restart). Implement this
/// interface yourself to back the cache with Hive, `shared_preferences`, or
/// sqflite if you need caching that survives a restart — just serialize
/// `entry.response.completeData` to JSON in your implementation.
abstract class ApiCacheStore {
  Future<CacheEntry?> read(String key);
  Future<void> write(String key, CacheEntry entry);
  Future<void> delete(String key);
  Future<void> clear();
}

/// Default, zero-setup cache store. Lives only in memory for the lifetime
/// of the process — perfectly fine for the common "avoid refetching the
/// same list twice in ten seconds" use case.
class MemoryCacheStore implements ApiCacheStore {
  final Map<String, CacheEntry> _store = {};

  @override
  Future<CacheEntry?> read(String key) async {
    final entry = _store[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _store.remove(key);
      return null;
    }
    return entry;
  }

  @override
  Future<void> write(String key, CacheEntry entry) async {
    _store[key] = entry;
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }
}

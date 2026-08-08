/// Per-call caching behaviour. Pass this to `get`/`post`/etc. to opt that
/// call into caching — calls without a [CacheOptions] are never cached.
///
/// ```dart
/// // Cache for 2 minutes, reuse across identical calls:
/// await api.get('/products', cache: const CacheOptions(ttl: Duration(minutes: 2)));
///
/// // Same call, but skip the cache this one time (e.g. pull-to-refresh):
/// await api.get('/products', cache: const CacheOptions(
///   ttl: Duration(minutes: 2),
///   forceRefresh: true,
/// ));
/// ```
class CacheOptions {
  /// How long a cached response stays valid.
  final Duration ttl;

  /// Bypass any cached value and hit the network, then overwrite the cache
  /// with the fresh result. Use this for pull-to-refresh / manual retry.
  final bool forceRefresh;

  /// Custom cache key. If omitted, one is derived from the method, path,
  /// and query params / body, so identical calls share a cache entry
  /// automatically.
  final String? key;

  const CacheOptions({
    this.ttl = const Duration(minutes: 5),
    this.forceRefresh = false,
    this.key,
  });
}

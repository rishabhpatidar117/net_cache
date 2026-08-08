# net_cache

A single, reusable networking layer for Flutter apps, extracted from the
patterns already in `alok_sell_manager` (`ApiService`, `ApiResponse`,
`ApiException`, `AppLogger`) and generalized so every package/feature — the
fallback summary screen included — can share **one** implementation instead
of each hand-rolling its own `try/catch` + Dio setup.

What it gives you, on top of plain Dio:

- **Centralized error handling** — every call funnels through one internal
  `try/catch`. You never write `try { ... } catch (e) { throw ApiException(e); }`
  yourself again; call sites just describe the request and either get an
  `ApiResponse` back or an `ApiException` thrown. A raw `DioException`,
  `FormatException`, or socket error never escapes to your UI code, so a bad
  response can't crash the app.
- **TTL caching with force refresh** — opt any `GET` call into caching for
  N minutes, and force-refresh it (pull-to-refresh, retry buttons) without
  changing the call shape.
- **Polling streams** — `client.stream(path, options: ApiStreamOptions(interval: ...))`
  hits the endpoint repeatedly, waiting `interval` *after each call
  finishes* (so the real gap is `interval + call time`, never overlapping
  itself), and keeps polling through errors instead of dying on the first one.
- **File-based logging** — same rotate/retain-by-age structure as the
  app's `AppLogger`, generalized so it's not tied to app-specific constants.
  Point your existing `LogViewerPage` at `ApiLogger.getAllLogFiles()` /
  `ApiLogger.getTodayLogs()` and it keeps working unchanged.

## Install

Copy the `net_cache/` folder into your app (e.g. as a local path
package), then in the consuming app's `pubspec.yaml`:

```yaml
dependencies:
  net_cache:
    git:
      url: https://github.com/rishabhpatidar117/net_cache.git
      ref: v1.0.0
```

## Setup (once, in `main()`)

```dart
import 'package:net_cache/net_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ApiLogger.init(); // optional but recommended — enables file logs

  SmartApiClient.init(ApiClientConfig(
    baseUrl: ApiConstant.baseUrl,
    tokenProvider: () => Storage.accessToken,
    tokentypeProvider: () => "Bearer",
    onUnauthorized: () => AppRouter.context.read<AuthCubit>().logout(),
  ));

  runApp(const MyApp());
}
```

`tokenProvider`,`tokentypeProvider` and `onUnauthorized` are callbacks instead of hard-coded
`Storage`/`AuthCubit` references (like the current `dio_client.dart` has),
so this package has zero dependency on your app's auth/router packages and
can be dropped into any project.

## Everyday calls

```dart
final api = SmartApiClient.instance;

try {
  final res = await api.get('/products');
  if (res.success) {
    final products = res.data as List;
  }
} on ApiException catch (e) {
  showSnackBar(e.error); // human-readable message, Laravel-style errors included
}

await api.post('/orders', data: {'productId': 12, 'qty': 2});
await api.put('/orders/12', data: {'qty': 3});
await api.delete('/orders/12');
await api.download('/invoices/12.pdf', savePath: '/path/to/save.pdf');
```

Every one of these can throw `ApiException` — that's the *only* exception
type this package ever throws, so one `on ApiException catch (e)` at the
call site (or in your Cubit/Bloc's error mapping) covers everything.

## Caching

Caching is **opt-in per call** — pass `cache:` only where it makes sense
(lists, dashboards, anything that doesn't need to be live every time):

```dart
// Cached for 2 minutes, reused across identical calls automatically.
final res = await api.get(
  '/dashboard/summary',
  cache: const CacheOptions(ttl: Duration(minutes: 2)),
);

// Pull-to-refresh: same call, but skip + overwrite the cache this once.
final fresh = await api.get(
  '/dashboard/summary',
  cache: const CacheOptions(ttl: Duration(minutes: 2), forceRefresh: true),
);
```

This is exactly the case you flagged with the fallback summary screen
calling the same API as other packages — give both call sites the same
`cache.key` (or let it auto-derive from method + path + params, which is
identical for identical calls) and they'll share one cached response
instead of hitting the network twice.

Default cache store is in-memory (cleared on app restart). To persist
across restarts, implement `ApiCacheStore` (Hive/`shared_preferences`/etc.)
and pass it as `ApiClientConfig(cacheStore: yourStore)`.

## Streams (polling)

```dart
final sub = api.stream(
  '/orders/active',
  options: const ApiStreamOptions(interval: Duration(seconds: 15)),
).listen(
  (res) => updateUi(res.data),
  onError: (e) => showTransientError((e as ApiException).error),
);

// later
await sub.cancel(); // stops the timer, no further calls
```

The wait is 15s **after each call finishes**, not a fixed 15s clock tick —
so a slow endpoint never gets a second request stacked on top of the first.
A failed poll calls `onError` but the stream keeps going; it only stops if
you cancel the subscription.

## Logging

```dart
await ApiLogger.init(
  retentionDays: 7,      // delete log files older than this
  maxFileSizeBytes: 2 * 1024 * 1024, // rotate past this size
);

ApiLogger.info('OrdersRepo', 'submitOrder', 'orderId=$id');
ApiLogger.error('OrdersRepo', 'submitOrder', 'failed: $e');
```

`ApiLogger.getAllLogFiles()` / `ApiLogger.getTodayLogs()` return exactly
what the existing `LogViewerPage` expects, so it can point at this package
instead of the app-local `AppLogger` with no UI changes.

## Multiple backends

`SmartApiClient.instance` is a convenience singleton for the common
single-backend case. If a feature needs to talk to a second API, just
construct another instance directly and hold onto it (DI, a static field in
that feature's module, etc.) — `SmartApiClient(config)` doesn't require
`init()`.

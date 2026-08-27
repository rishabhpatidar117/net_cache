# net_cache — Agent Guide

A centralized, reusable networking layer for Flutter/Dart apps built on top of [Dio](https://pub.dev/packages/dio). Provides HTTP client, TTL caching, polling streams, structured logging, and unified error handling through a single package.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Installation](#installation)
3. [Quick Start](#quick-start)
4. [ApiClientConfig Reference](#apiclientconfig-reference)
5. [HTTP Methods](#http-methods)
6. [Caching](#caching)
7. [Polling Streams](#polling-streams)
8. [Error Handling](#error-handling)
9. [Authentication](#authentication)
10. [Logging](#logging)
11. [Multi-Backend](#multi-backend)
12. [Custom Cache Store](#custom-cache-store)
13. [Custom Interceptors](#custom-interceptors)
14. [Exported API Reference](#exported-api-reference)
15. [Architecture & Design Decisions](#architecture--design-decisions)

---

## Project Overview

**Package:** `net_cache` (v1.0.7)
**Language:** Dart (SDK >=3.11.5)
**Framework:** Flutter
**Primary dependency:** `dio ^5.4.0`

### Core Principles

- **Single exception type** — `ApiException` is the only exception thrown. Raw `DioException`, `FormatException`, socket errors never escape.
- **Opt-in caching** — Caching is per-call (GET only), not automatic. Pass `cache: CacheOptions(...)` only where needed.
- **Callback-based auth** — `tokenProvider`, `tokentypeProvider`, `onUnauthorized` are callbacks, not hard-coded references. Zero dependency on any specific auth/storage implementation.
- **Two Dio instances** — One for authenticated requests (with auth interceptor), one for public/unauthenticated requests.
- **Centralized try/catch** — All HTTP calls funnel through one internal `_execute` method. Call sites never write their own `try/catch` for network errors.

---

## Installation

Add to your app's `pubspec.yaml`:

```yaml
dependencies:
  net_cache:
    git:
      url: https://github.com/rishabhpatidar117/net_cache.git
      ref: v1.0.0
```

Or as a local path package:

```yaml
dependencies:
  net_cache:
    path: ../packages/net_cache
```

---

## Quick Start

```dart
import 'package:net_cache/net_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Step 1: Initialize logger (optional but recommended)
  await ApiLogger.init(
    folderName: 'api_logs',
    enableFileLogging: true,
    enableConsoleLogging: true,
    retentionDays: 7,
    maxFileSizeBytes: 2 * 1024 * 1024,
  );

  // Step 2: Initialize the HTTP client singleton
  SmartApiClient.init(ApiClientConfig(
    baseUrl: 'https://api.myapp.com/v1',
    tokenProvider: () => Storage.accessToken,
    tokentypeProvider: () => 'Bearer',
    onUnauthorized: () => AppRouter.context.read<AuthCubit>().logout(),
  ));

  runApp(const MyApp());
}
```

After initialization, use anywhere:

```dart
final api = SmartApiClient.instance;
final res = await api.get('/products');
if (res.success) {
  final products = res.data as List;
}
```

---

## ApiClientConfig Reference

All fields for `ApiClientConfig`:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `baseUrl` | `String` (required) | — | Base URL for all API requests |
| `connectTimeout` | `Duration` | `30s` | Connection timeout |
| `receiveTimeout` | `Duration` | `30s` | Receive timeout |
| `sendTimeout` | `Duration` | `30s` | Send timeout |
| `defaultHeaders` | `Map<String, dynamic>` | `{'Content-Type': 'application/json', 'Accept': 'application/json'}` | Headers sent on every request |
| `tokenProvider` | `FutureOr<String?> Function()?` | `null` | Callback to fetch current auth token dynamically |
| `tokentypeProvider` | `FutureOr<String?> Function()?` | `null` | Callback to fetch token type (e.g., `"Bearer"`) |
| `onUnauthorized` | `void Function()?` | `null` | Called when a 401 response is received |
| `extraInterceptors` | `List<Interceptor>` | `[]` | Additional Dio interceptors to attach |
| `enableHttpLogging` | `bool` | `true` | Enable request/response logging via ApiLogger |
| `cacheStore` | `ApiCacheStore` | `MemoryCacheStore()` | Cache storage backend |
| `authenticatedDio` | `Dio?` | `null` | Pre-built Dio instance for authenticated requests |
| `publicDio` | `Dio?` | `null` | Pre-built Dio instance for public requests |
| `httpClientAdapter` | `HttpClientAdapter?` | `null` | Custom HTTP adapter (useful for testing/mocking) |

### Minimal Config

```dart
SmartApiClient.init(ApiClientConfig(
  baseUrl: 'https://api.myapp.com',
));
```

### Full Config

```dart
SmartApiClient.init(ApiClientConfig(
  baseUrl: 'https://api.myapp.com',
  connectTimeout: Duration(seconds: 15),
  receiveTimeout: Duration(seconds: 15),
  sendTimeout: Duration(seconds: 15),
  defaultHeaders: {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'X-Custom': 'value',
  },
  tokenProvider: () async => await SecureStorage.getToken(),
  tokentypeProvider: () => 'Bearer',
  onUnauthorized: () => AuthService.logout(),
  enableHttpLogging: true,
  cacheStore: MemoryCacheStore(),
  extraInterceptors: [
    InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers['X-Request-ID'] = uuid.v4();
        handler.next(options);
      },
    ),
  ],
));
```

---

## HTTP Methods

All methods return `Future<ApiResponse>` (except `download` which returns `Future<Response>`).

### GET

```dart
final res = await api.get('/products');

// With query parameters
final res = await api.get('/products', params: {'category': 'electronics', 'page': 1});

// Public (no auth header)
final res = await api.get('/public/products', authenticated: false);

// With caching
final res = await api.get('/dashboard', cache: const CacheOptions(ttl: Duration(minutes: 5)));

// With cancel token
final token = CancelToken();
final res = await api.get('/slow-endpoint', cancelToken: token);
```

### POST

```dart
// JSON body
await api.post('/orders', data: {'productId': 12, 'qty': 2});

// With query params
await api.post('/orders', data: {'qty': 2}, params: {'version': 'v2'});

// Multipart form upload
await api.post('/upload', formData: FormData.fromMap({
  'file': await MultipartFile.fromFile('/path/to/image.png'),
  'name': 'profile-pic',
}));
```

### PUT

```dart
await api.put('/orders/12', data: {'qty': 3});
await api.put('/profile', formData: FormData.fromMap({
  'avatar': await MultipartFile.fromFile('/path/to/avatar.jpg'),
}));
```

### PATCH

```dart
await api.patch('/orders/12', data: {'status': 'shipped'});
```

### DELETE

```dart
await api.delete('/orders/12');
await api.delete('/orders/12', data: {'reason': 'cancelled'});
```

### DOWNLOAD

```dart
// Returns raw Dio Response, not ApiResponse
final response = await api.download(
  '/invoices/12.pdf',
  savePath: '/local/path/invoice.pdf',
);

// With progress tracking
await api.download(
  '/large-file.zip',
  savePath: '/local/path/file.zip',
  onReceiveProgress: (received, total) {
    print('Progress: ${(received / total * 100).toStringAsFixed(0)}%');
  },
);
```

### CANCEL a Request

```dart
final token = CancelToken();

// Start request
api.get('/slow-endpoint', cancelToken: token);

// Cancel it (e.g., user navigated away)
token.cancel('User navigated away');
```

### Method Parameters Summary

| Parameter | Type | Available On | Description |
|-----------|------|--------------|-------------|
| `path` | `String` | All | URL path (appended to baseUrl) |
| `data` | `dynamic` | post, put, patch, delete | Request body |
| `formData` | `FormData` | post, put, patch | Multipart form data |
| `params` | `Map<String, dynamic>?` | All | Query parameters |
| `authenticated` | `bool` | All (default: `true`) | Whether to use auth interceptor |
| `cache` | `CacheOptions?` | get, stream | Per-call cache configuration |
| `cancelToken` | `CancelToken?` | All | Token to cancel the request |
| `savePath` | `String` | download | Local file path to save to |
| `onReceiveProgress` | `ProgressCallback?` | download | Progress callback |

---

## Caching

Caching is **opt-in per call** and only works for GET requests.

### CacheOptions

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `ttl` | `Duration` | `5 minutes` | How long a cached response stays valid |
| `forceRefresh` | `bool` | `false` | Bypass cache, hit network, overwrite cache entry |
| `key` | `String?` | `null` | Custom cache key (auto-derived from method+path+params if omitted) |

### Basic Caching

```dart
// Cache for 2 minutes
final res = await api.get(
  '/dashboard/summary',
  cache: const CacheOptions(ttl: Duration(minutes: 2)),
);
```

### Force Refresh (Pull-to-Refresh)

```dart
final fresh = await api.get(
  '/dashboard/summary',
  cache: const CacheOptions(
    ttl: Duration(minutes: 2),
    forceRefresh: true, // skips cache, fetches from network, overwrites cache
  ),
);
```

### Custom Cache Key

Share cache across different call sites by using the same key:

```dart
// In feature A
final res = await api.get(
  '/products',
  cache: const CacheOptions(key: 'products-list', ttl: Duration(minutes: 5)),
);

// In feature B — same cache entry
final res = await api.get(
  '/products',
  cache: const CacheOptions(key: 'products-list', ttl: Duration(minutes: 5)),
);
```

### Auto-Derived Cache Key

If no `key` is provided, the key is derived from:
```
METHOD:path?sortedParam1=val1&sortedParam2=val2#data
```
Params are sorted alphabetically for deterministic keys.

### Cache Management

```dart
// Clear all cached entries
await api.clearCache();

// Evict a specific entry by key
await api.evictCache('products-list');
```

### Cache from Response

Check if a response came from cache:

```dart
final res = await api.get('/dashboard', cache: const CacheOptions(ttl: Duration(minutes: 2)));
if (res.fromCache) {
  // Show stale indicator or background refresh
}
```

### Default Cache Store

`MemoryCacheStore` — in-memory map, cleared on app restart. To persist across restarts, implement `ApiCacheStore` (see [Custom Cache Store](#custom-cache-store)).

---

## Polling Streams

Hit an endpoint repeatedly at a fixed interval. The wait starts **after each call finishes**, preventing overlap on slow endpoints.

### ApiStreamOptions

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `interval` | `Duration` | `10 seconds` | Wait time after each call completes before the next |
| `immediate` | `bool` | `true` | If `true`, first call fires immediately; if `false`, waits `interval` first |

### Basic Stream

```dart
final subscription = api.stream(
  '/orders/active',
  options: const ApiStreamOptions(interval: Duration(seconds: 15)),
).listen(
  (res) {
    if (res.fromCache) {
      // Show stale data indicator
    }
    updateUi(res.data);
  },
  onError: (e) {
    // e is ApiException — stream keeps polling after errors
    showTransientError((e as ApiException).error);
  },
);

// Stop polling
await subscription.cancel();
```

### Stream Behavior

- **Non-overlapping:** If a call takes 5s and interval is 15s, the next call starts 20s after the previous one started.
- **Error-resilient:** Errors emit via `onError` but the stream keeps polling. Only cancellation stops it.
- **Immediate flag:** Set `immediate: false` to delay the first call by `interval`.

### Stream with Cancellation Token

```dart
final cancelToken = CancelToken();

final subscription = api.stream(
  '/orders/active',
  options: const ApiStreamOptions(interval: Duration(seconds: 10)),
).listen((res) => updateUi(res.data));

// Cancel via token (also stops the stream)
cancelToken.cancel('Component disposed');
```

---

## Error Handling

### ApiException

The only exception type thrown by this package.

| Field | Type | Description |
|-------|------|-------------|
| `source` | `dynamic` | Original error object (DioException, String, Map, etc.) |
| `error` | `String` | Lazily computed human-readable message via `getErrorMessage()` |
| `statusCode` | `int?` | HTTP status code (extracted from source if available) |

`toString()` returns the `error` string.

### Usage

```dart
try {
  final res = await api.get('/protected-data');
  if (res.success) {
    process(res.data);
  } else {
    showSnackBar(res.message);
  }
} on ApiException catch (e) {
  showSnackBar(e.error);       // human-readable message
  log(e.statusCode);           // HTTP status code (if available)
  log(e.source);               // original error object
}
```

### getErrorMessage() Normalization

The `getErrorMessage(Object error)` function (top-level, exported) handles:

| Error Source | Handling |
|--------------|----------|
| `ApiException` | Recurses on `.source` |
| `Map` with `errors`/`error`/`message`/`msg`/`detail` keys | Extracts and flattens nested error messages |
| `List` of errors | Joins into readable string |
| `ApiResponse` | Uses `.message` or extracts from `.completeData` |
| `DioException` (cancel) | `"Request was canceled."` |
| `DioException` (timeout) | `"Request timed out. Please check your connection and try again."` |
| `DioException` (badCertificate) | `"Invalid SSL certificate."` |
| `DioException` (connectionError) | `"No internet connection. Please check your network settings."` |
| `DioException` (badResponse) | Parses response body for error messages |
| Fallback | `.toString()` |

### Laravel-Style Nested Validation Errors

Handles responses like:
```json
{
  "errors": {
    "email": ["The email field is required.", "The email must be a valid email address."],
    "password": ["The password must be at least 8 characters."]
  }
}
```

Flattens to: `"The email field is required. The email must be a valid email address. The password must be at least 8 characters."`

---

## Authentication

### How It Works

`SmartApiClient` maintains two Dio instances:
- `_authDio` — has an interceptor that adds auth headers
- `_publicDio` — no auth headers

The `authenticated` parameter on each method selects which instance to use (default: `true`).

### Auth Interceptor Behavior (on `_authDio`)

1. Sets `content-type`, `accept`, `User-Agent` headers
2. Calls `tokenProvider()` to get the latest token
3. Calls `tokentypeProvider()` to get the token type (e.g., `"Bearer"`)
4. Sets `Authorization: <type> <token>` header
5. On 401 response, calls `onUnauthorized` callback

### Token as Callback

`tokenProvider` is a callback (not a stored value) so it always reads the **latest** token. This decouples the package from any specific storage implementation.

```dart
SmartApiClient.init(ApiClientConfig(
  baseUrl: 'https://api.myapp.com',
  tokenProvider: () async {
    // Read from secure storage, shared preferences, etc.
    return await FlutterSecureStorage.read(key: 'access_token');
  },
  tokentypeProvider: () => 'Bearer',
  onUnauthorized: () {
    // Navigate to login, clear state, etc.
    context.read<AuthCubit>().logout();
  },
));
```

### Authenticated vs Public Requests

```dart
// Authenticated (default) — uses tokenProvider
await api.get('/profile');

// Public — no Authorization header
await api.get('/public/products', authenticated: false);
await api.get('/health-check', authenticated: false);
```

---

## Logging

### ApiLogger.init() Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `folderName` | `String` | `'api_logs'` | Subdirectory under app documents directory |
| `enableFileLogging` | `bool` | `true` | Write logs to disk |
| `enableConsoleLogging` | `bool` | `true` | Print logs to console via `debugPrint` |
| `retentionDays` | `int` | `7` | Delete log files older than this |
| `maxFileSizeBytes` | `int` | `2 * 1024 * 1024` (2 MB) | Rotate file when it exceeds this size |

### Initialization

```dart
await ApiLogger.init(
  folderName: 'api_logs',
  enableFileLogging: true,
  enableConsoleLogging: true,
  retentionDays: 7,
  maxFileSizeBytes: 2 * 1024 * 1024,
);
```

### Log Methods

| Method | Level | Signature | Use Case |
|--------|-------|-----------|----------|
| `log` | `LOG` | `log(Object? object)` | Generic/raw logging |
| `info` | `INFO` | `info(String module, String action, String detail)` | Informational events |
| `warn` | `WARN` | `warn(String module, String action, String detail)` | Warnings |
| `error` | `ERROR` | `error(String module, String action, String detail)` | Errors without stack trace |
| `errorTrace` | `ERROR` | `errorTrace(String module, String action, Object error, StackTrace stackTrace)` | Errors with stack trace |

### Log Format

```
[HH:mm:ss] [LEVEL] module :: action :: detail
```

Example:
```
[14:32:05] [INFO] OrdersRepo :: submitOrder :: orderId=123
[14:32:06] [ERROR] OrdersRepo :: submitOrder :: failed: Connection timeout
```

### Usage

```dart
ApiLogger.info('OrdersRepo', 'submitOrder', 'orderId=$id');
ApiLogger.warn('ProductsRepo', 'fetchList', 'cache miss, fetching from network');
ApiLogger.error('OrdersRepo', 'submitOrder', 'failed: $e');
ApiLogger.errorTrace('AuthRepo', 'login', error, stackTrace);
```

### Log File Operations

```dart
// Get today's log content as a string
final todayLogs = await ApiLogger.getTodayLogs();

// Get all log files (sorted newest first)
final allFiles = await ApiLogger.getAllLogFiles();
```

These methods are compatible with existing `LogViewerPage` UIs — point them at `ApiLogger.getAllLogFiles()` / `ApiLogger.getTodayLogs()` with no UI changes.

### Automatic Behavior

- **Rotation:** When a log file exceeds `maxFileSizeBytes`, it is renamed to `.1.txt` and a new file is created.
- **Cleanup:** On `init()`, files older than `retentionDays` are deleted automatically.

---

## Multi-Backend

For apps that talk to more than one API:

### Direct Instantiation (No Singleton)

```dart
final clientA = SmartApiClient(ApiClientConfig(
  baseUrl: 'https://api-a.com',
  tokenProvider: () => tokenA,
));

final clientB = SmartApiClient(ApiClientConfig(
  baseUrl: 'https://api-b.com',
  tokenProvider: () => tokenB,
));

// Use independently
final resA = await clientA.get('/endpoint');
final resB = await clientB.get('/endpoint');
```

### Singleton + Direct Mix

```dart
// Main backend via singleton
SmartApiClient.init(ApiClientConfig(baseUrl: 'https://api.myapp.com'));

// Secondary backend via direct instance
final analyticsClient = SmartApiClient(ApiClientConfig(
  baseUrl: 'https://analytics.myapp.com',
));
```

---

## Custom Cache Store

Implement the `ApiCacheStore` interface for persistent caching (Hive, shared_preferences, sqflite, etc.):

```dart
class PersistentCacheStore implements ApiCacheStore {
  // Your storage implementation

  @override
  Future<CacheEntry?> read(String key) async {
    // Retrieve from persistent storage
    // Return null if not found or expired
  }

  @override
  Future<void> write(String key, CacheEntry entry) async {
    // Store in persistent storage
  }

  @override
  Future<void> delete(String key) async {
    // Remove from persistent storage
  }

  @override
  Future<void> clear() async {
    // Remove all entries from persistent storage
  }
}
```

### Use It

```dart
SmartApiClient.init(ApiClientConfig(
  baseUrl: 'https://api.myapp.com',
  cacheStore: PersistentCacheStore(),
));
```

### CacheEntry Structure

```dart
class CacheEntry {
  final ApiResponse response;
  final DateTime expiresAt;
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
```

---

## Custom Interceptors

Add Dio interceptors via `extraInterceptors`:

```dart
SmartApiClient.init(ApiClientConfig(
  baseUrl: 'https://api.myapp.com',
  extraInterceptors: [
    InterceptorsWrapper(
      onRequest: (options, handler) {
        // Add custom header
        options.headers['X-Request-ID'] = uuid.v4();
        handler.next(options);
      },
      onResponse: (response, handler) {
        // Transform response
        handler.next(response);
      },
      onError: (error, handler) {
        // Handle specific error codes
        if (error.response?.statusCode == 429) {
          // Rate limited — retry after delay
        }
        handler.next(error);
      },
    ),
  ],
));
```

### Accessing Raw Dio

For advanced use cases requiring raw Dio features:

```dart
final dio = SmartApiClient.instance.authenticatedDio;
// Use dio directly for features not covered by SmartApiClient
```

---

## Exported API Reference

Everything accessible via `import 'package:net_cache/net_cache.dart';`:

### Classes

| Class | File | Purpose |
|-------|------|---------|
| `SmartApiClient` | `smart_api_client.dart` | Main HTTP client (singleton + direct instantiation) |
| `ApiClientConfig` | `api_client_config.dart` | Configuration object for SmartApiClient |
| `ApiResponse` | `api_response.dart` | Normalized response wrapper |
| `ApiException` | `api_exception.dart` | Single exception type for all errors |
| `ApiLogger` | `api_logger.dart` | File-backed structured logger |
| `CacheOptions` | `cache_options.dart` | Per-call cache configuration |
| `CacheEntry` | `cache_store.dart` | Cached response + expiration |
| `ApiCacheStore` | `cache_store.dart` | Cache storage interface (abstract) |
| `MemoryCacheStore` | `cache_store.dart` | Default in-memory cache implementation |
| `ApiStreamOptions` | `api_stream_options.dart` | Polling stream configuration |

### Top-Level Functions

| Function | File | Purpose |
|----------|------|---------|
| `getErrorMessage(Object error)` | `api_response.dart` | Convert any error to human-readable string |

### Re-Exported from Dio

| Symbol | Purpose |
|--------|---------|
| `FormData` | Multipart form data construction |
| `MultipartFile` | File uploads within FormData |
| `CancelToken` | Cancel in-flight requests |
| `ProgressCallback` | Download/upload progress tracking |
| `Interceptor` | Base class for custom interceptors |
| `InterceptorsWrapper` | Create custom interceptors inline |

---

## Architecture & Design Decisions

### 1. Single Exception Type

`ApiException` is the only exception ever thrown. A single `on ApiException catch (e)` at the call site covers everything. Raw `DioException`, `FormatException`, socket errors never escape.

### 2. Centralized Try/Catch

All HTTP calls go through `_execute()`. Call sites never write their own `try/catch` for network errors. The internal handler:
- Checks cache before network (for GET with CacheOptions)
- Writes to cache on success (if cacheable)
- Wraps errors in `ApiException`
- Logs successes and errors via `ApiLogger`

### 3. Opt-in Caching

Caching is per-call (GET only), not automatic. You pass `cache: CacheOptions(...)` only where it makes sense — avoids stale data surprises on endpoints that must always be live.

### 4. Two Dio Instances

- `_authDio` — has auth interceptor, used when `authenticated: true` (default)
- `_publicDio` — no auth headers, used when `authenticated: false`

This avoids toggling interceptors on/off per request.

### 5. Token as Callback

`tokenProvider` is a callback, not a stored value. It always reads the latest token from wherever the app stores it. This keeps the package decoupled from any specific auth/storage implementation.

### 6. Stream Polling Design

The wait starts **after** each call finishes, not on a fixed clock. A 15-second interval with a 5-second call = 20 seconds between requests, never overlapping. Errors don't stop the stream.

### 7. Error Message Normalization

`getErrorMessage()` handles Laravel-style nested validation errors, plain strings, Dio exceptions, nested Maps/Lists, and falls back to `.toString()`. Designed for maximum compatibility with different backend error formats.

### 8. Logging Compatibility

Log file format and API (`getAllLogFiles()`, `getTodayLogs()`) are designed to be compatible with the host app's existing `LogViewerPage`. No UI changes needed when switching from app-local logger to `ApiLogger`.

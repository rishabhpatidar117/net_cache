import 'dart:async';

import 'package:dio/dio.dart';

import '../cache/cache_options.dart';
import '../cache/cache_store.dart';
import '../exceptions/api_exception.dart';
import '../logging/api_logger.dart';
import '../response/api_response.dart';
import '../stream/api_stream_options.dart';
import 'api_client_config.dart';

/// The single entry point for every API call in the app.
///
/// Every method here funnels through one private [_execute] that owns the
/// only try/catch in the whole client: it always returns an [ApiResponse]
/// on success or throws an [ApiException] on failure — a raw
/// [DioException], [FormatException], socket error, etc. never escapes to
/// call sites. That's the "reuse the try/catch wrap" part: individual
/// `get`/`post`/`put`/`delete` calls do zero error handling of their own,
/// they just describe the request.
///
/// ```dart
/// // once, e.g. in main():
/// SmartApiClient.init(ApiClientConfig(
///   baseUrl: 'https://api.myapp.com',
///   tokenProvider: () => Storage.accessToken,
///   onUnauthorized: () => AppRouter.context.read<AuthCubit>().logout(),
/// ));
///
/// // anywhere in the app:
/// try {
///   final res = await SmartApiClient.instance.get(
///     '/products',
///     cache: const CacheOptions(ttl: Duration(minutes: 2)),
///   );
/// } on ApiException catch (e) {
///   showSnackBar(e.error);
/// }
/// ```
class SmartApiClient {
  SmartApiClient(this.config)
    : _authDio = config.authenticatedDio ?? _buildDio(config),
      _publicDio = config.publicDio ?? _buildDio(config) {
    _attachInterceptors();
  }

  final ApiClientConfig config;
  final Dio _authDio;
  final Dio _publicDio;

  ApiCacheStore get _cache => config.cacheStore;

  /// Direct access to the underlying authenticated/public Dio instances,
  /// for the rare case you need a Dio-specific feature this client doesn't
  /// wrap (e.g. a raw multipart upload with custom progress handling).
  /// Prefer the typed methods below wherever possible so you keep the
  /// centralized error handling, caching, and logging.
  Dio get authenticatedDio => _authDio;
  Dio get publicDio => _publicDio;

  // ───────────────────────── global / singleton access ─────────────────────

  static SmartApiClient? _defaultInstance;

  /// Call once (e.g. in `main()`) to set up the app-wide client, then reach
  /// it anywhere via [SmartApiClient.instance]. If your app talks to more
  /// than one backend, skip this and just construct `SmartApiClient(config)`
  /// instances directly instead — [instance] is a convenience, not a
  /// requirement.
  static void init(ApiClientConfig config) {
    _defaultInstance = SmartApiClient(config);
  }

  static SmartApiClient get instance {
    final i = _defaultInstance;
    if (i == null) {
      throw StateError(
        'SmartApiClient.instance was used before SmartApiClient.init(config) '
        'was called. Call SmartApiClient.init(...) once at startup, or '
        'construct SmartApiClient(config) directly and pass it around.',
      );
    }
    return i;
  }

  // ─────────────────────────────── setup ────────────────────────────────

  static Dio _buildDio(ApiClientConfig config) {
    return Dio(
      BaseOptions(
        baseUrl: config.baseUrl,
        connectTimeout: config.connectTimeout,
        receiveTimeout: config.receiveTimeout,
        sendTimeout: config.sendTimeout,
        headers: Map<String, dynamic>.from(config.defaultHeaders),
      ),
    );
  }

  void _attachInterceptors() {
    _authDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final provider = config.tokenProvider;
          if (provider != null) {
            final token = await provider();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
        onError: (err, handler) {
          if (err.response?.statusCode == 401) {
            config.onUnauthorized?.call();
          }
          handler.next(err);
        },
      ),
    );

    for (final interceptor in config.extraInterceptors) {
      _authDio.interceptors.add(interceptor);
    }

    if (config.enableHttpLogging) {
      _authDio.interceptors.add(_logInterceptor());
      _publicDio.interceptors.add(_logInterceptor());
    }
  }

  Interceptor _logInterceptor() {
    return LogInterceptor(
      requestBody: false,
      responseBody: false,
      requestUrl: true,
      request: false,
      requestHeader: false,
      responseUrl: false,
      responseHeader: false,
      error: true,
      logPrint: (obj) => ApiLogger.log(obj),
    );
  }

  // ─────────────────────────── public HTTP methods ──────────────────────

  Future<ApiResponse> get(
    String path, {
    Map<String, dynamic>? params,
    bool authenticated = true,
    CacheOptions? cache,
    CancelToken? cancelToken,
  }) {
    return _execute(
      method: 'GET',
      path: path,
      params: params,
      authenticated: authenticated,
      cache: cache,
      cancelToken: cancelToken,
    );
  }

  Future<ApiResponse> post(
    String path, {
    Map<String, dynamic>? data,
    FormData? formData,
    Map<String, dynamic>? params,
    bool authenticated = true,
    CancelToken? cancelToken,
  }) {
    return _execute(
      method: 'POST',
      path: path,
      data: data,
      formData: formData,
      params: params,
      authenticated: authenticated,
      cancelToken: cancelToken,
    );
  }

  Future<ApiResponse> put(
    String path, {
    Map<String, dynamic>? data,
    FormData? formData,
    Map<String, dynamic>? params,
    bool authenticated = true,
    CancelToken? cancelToken,
  }) {
    return _execute(
      method: 'PUT',
      path: path,
      data: data,
      formData: formData,
      params: params,
      authenticated: authenticated,
      cancelToken: cancelToken,
    );
  }

  Future<ApiResponse> patch(
    String path, {
    Map<String, dynamic>? data,
    FormData? formData,
    Map<String, dynamic>? params,
    bool authenticated = true,
    CancelToken? cancelToken,
  }) {
    return _execute(
      method: 'PATCH',
      path: path,
      data: data,
      formData: formData,
      params: params,
      authenticated: authenticated,
      cancelToken: cancelToken,
    );
  }

  Future<ApiResponse> delete(
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? params,
    bool authenticated = true,
    CancelToken? cancelToken,
  }) {
    return _execute(
      method: 'DELETE',
      path: path,
      data: data,
      params: params,
      authenticated: authenticated,
      cancelToken: cancelToken,
    );
  }

  /// Downloads a file. Kept outside [_execute] because it returns a raw
  /// Dio [Response] (there's no JSON body to normalize into an
  /// [ApiResponse]) — but still gets the same centralized try/catch ->
  /// [ApiException] guarantee and logging as every other call.
  Future<Response> download(
    String path, {
    required String savePath,
    Map<String, dynamic>? params,
    bool authenticated = true,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final dio = authenticated ? _authDio : _publicDio;
      final response = await dio.download(
        path,
        savePath,
        queryParameters: params,
        onReceiveProgress: onReceiveProgress,
        cancelToken: cancelToken,
      );
      ApiLogger.info(
        'SmartApiClient',
        'DOWNLOAD',
        '$path :: saved to $savePath',
      );
      return response;
    } catch (e, st) {
      ApiLogger.errorTrace('SmartApiClient', 'DOWNLOAD', e, st);
      throw ApiException(e);
    }
  }

  // ────────────────────────────── streaming ─────────────────────────────

  /// Returns a [Stream] that calls [path] repeatedly, waiting
  /// [ApiStreamOptions.interval] *after each call finishes* before firing
  /// the next one — so the real gap between requests is
  /// `interval + <call duration>`, and a slow response never overlaps the
  /// next poll.
  ///
  /// A failed call does **not** end the stream: it calls
  /// [StreamController.addError] with an [ApiException] and keeps polling,
  /// so a listener can do:
  ///
  /// ```dart
  /// SmartApiClient.instance.stream('/orders/active').listen(
  ///   (res) => updateUi(res.data),
  ///   onError: (e) => showTransientError((e as ApiException).error),
  /// );
  /// ```
  ///
  /// Cancel by cancelling the stream subscription — that stops the timer
  /// and no further calls are made.
  Stream<ApiResponse> stream(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? params,
    dynamic data,
    bool authenticated = true,
    CacheOptions? cache,
    ApiStreamOptions options = const ApiStreamOptions(),
  }) {
    late StreamController<ApiResponse> controller;
    Timer? timer;
    var cancelled = false;

    Future<void> tick() async {
      if (cancelled) return;
      try {
        final res = await _execute(
          method: method,
          path: path,
          params: params,
          data: data,
          authenticated: authenticated,
          cache: cache,
        );
        if (!cancelled && !controller.isClosed) controller.add(res);
      } catch (e) {
        if (!cancelled && !controller.isClosed) controller.addError(e);
      } finally {
        if (!cancelled && !controller.isClosed) {
          timer = Timer(options.interval, tick);
        }
      }
    }

    controller = StreamController<ApiResponse>(
      onListen: () {
        if (options.immediate) {
          tick();
        } else {
          timer = Timer(options.interval, tick);
        }
      },
      onCancel: () {
        cancelled = true;
        timer?.cancel();
      },
    );

    return controller.stream;
  }

  // ──────────────────────────────── cache ────────────────────────────────

  /// Clears every cached response across all calls made through this
  /// client instance.
  Future<void> clearCache() => _cache.clear();

  /// Clears the cache entry for one specific call. Pass the same [key] you
  /// gave that call's [CacheOptions.key], or omit it if you let the client
  /// derive the key automatically and don't know it offhand — in that case
  /// use [clearCache] instead.
  Future<void> evictCache(String key) => _cache.delete(key);

  // ────────────────────────────── internal core ──────────────────────────

  Future<ApiResponse> _execute({
    required String method,
    required String path,
    Map<String, dynamic>? params,
    dynamic data,
    FormData? formData,
    bool authenticated = true,
    CacheOptions? cache,
    CancelToken? cancelToken,
  }) async {
    final upperMethod = method.toUpperCase();
    final cacheable = cache != null && upperMethod == 'GET';
    final cacheKey = cacheable
        ? (cache.key ?? _buildCacheKey(upperMethod, path, params, data))
        : null;

    if (cacheable && !cache.forceRefresh) {
      final cached = await _cache.read(cacheKey!);
      if (cached != null) {
        ApiLogger.info(
          'SmartApiClient',
          upperMethod,
          '$path :: cache hit ($cacheKey)',
        );
        return cached.response.asCached();
      }
    }

    try {
      final dio = authenticated ? _authDio : _publicDio;
      late Response response;

      switch (upperMethod) {
        case 'GET':
          response = await dio.get(
            path,
            queryParameters: params,
            cancelToken: cancelToken,
          );
          break;
        case 'POST':
          response = await dio.post(
            path,
            data: formData ?? data,
            queryParameters: params,
            cancelToken: cancelToken,
          );
          break;
        case 'PUT':
          response = await dio.put(
            path,
            data: formData ?? data,
            queryParameters: params,
            cancelToken: cancelToken,
          );
          break;
        case 'PATCH':
          response = await dio.patch(
            path,
            data: formData ?? data,
            queryParameters: params,
            cancelToken: cancelToken,
          );
          break;
        case 'DELETE':
          response = await dio.delete(
            path,
            data: data,
            queryParameters: params,
            cancelToken: cancelToken,
          );
          break;
        default:
          throw ApiException('Unsupported HTTP method "$method".');
      }

      final apiResponse = ApiResponse.fromResponse(response);

      if (cacheable) {
        await _cache.write(
          cacheKey!,
          CacheEntry(
            response: apiResponse,
            expiresAt: DateTime.now().add(cache.ttl),
          ),
        );
      }

      ApiLogger.info(
        'SmartApiClient',
        upperMethod,
        '$path :: success=${apiResponse.success}',
      );
      return apiResponse;
    } on ApiException {
      // Already logged + wrapped at the point it was thrown (e.g. inside
      // ApiResponse.fromResponse) — just let it through untouched.
      rethrow;
    } catch (e, st) {
      ApiLogger.errorTrace('SmartApiClient', upperMethod, e, st);
      throw ApiException(e);
    }
  }

  String _buildCacheKey(
    String method,
    String path,
    Map<String, dynamic>? params,
    dynamic data,
  ) {
    final buffer = StringBuffer('$method:$path');
    if (params != null && params.isNotEmpty) {
      final sortedKeys = params.keys.toList()..sort();
      buffer.write('?${sortedKeys.map((k) => '$k=${params[k]}').join('&')}');
    }
    if (data != null) {
      buffer.write('#$data');
    }
    return buffer.toString();
  }
}

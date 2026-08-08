import 'dart:async';

import 'package:dio/dio.dart';

import '../cache/cache_store.dart';

/// Everything [SmartApiClient] needs to know about your backend. Build one
/// of these once (typically as a singleton / DI-registered instance) and
/// reuse it across the app — that's what makes this "global".
class ApiClientConfig {
  /// Base URL, e.g. `https://api.myapp.com/v1`.
  final String baseUrl;

  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Duration sendTimeout;

  /// Headers applied to every request (both authenticated and public).
  final Map<String, dynamic> defaultHeaders;

  /// Called on every outgoing *authenticated* request to fetch the current
  /// token. Return null/empty to send the request without an
  /// `Authorization` header. Kept as a callback (rather than a fixed
  /// string) so it always reads the latest token, same as the app's
  /// `Storage.accessToken` lookup in its auth interceptor.
  final FutureOr<String?> Function()? tokenProvider;
  final FutureOr<String?> Function()? tokentypeProvider;

  /// Called when a request comes back 401. Use this to log the user out /
  /// redirect to login, same as the app's existing
  /// `AuthCubit.logout()` call — this package stays decoupled from any
  /// specific bloc/router by taking it as a callback instead.
  final void Function()? onUnauthorized;

  /// Extra Dio interceptors to attach (e.g. an offline-queue interceptor),
  /// applied after the built-in auth interceptor.
  final List<Interceptor> extraInterceptors;

  /// Log every request/response via [ApiLogger] as well as `debugPrint` in
  /// debug builds (mirrors the app's `LogInterceptor` usage in
  /// `dio_client.dart`).
  final bool enableHttpLogging;

  /// Cache backend. Defaults to an in-memory store; pass your own
  /// [ApiCacheStore] to persist across restarts.
  final ApiCacheStore cacheStore;

  /// Provide your own [Dio] instances instead of letting the client build
  /// them (useful for testing with a mock adapter). If omitted, the client
  /// builds two clients internally — one with the auth interceptor, one
  /// without — from the fields above.
  final Dio? authenticatedDio;
  final Dio? publicDio;

  ApiClientConfig({
    required this.baseUrl,
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(seconds: 30),
    this.defaultHeaders = const {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    this.tokenProvider,
    this.tokentypeProvider,
    this.onUnauthorized,
    this.extraInterceptors = const [],
    this.enableHttpLogging = true,
    ApiCacheStore? cacheStore,
    this.authenticatedDio,
    this.publicDio,
  }) : cacheStore = cacheStore ?? MemoryCacheStore();
}

/// A reusable, centralized networking layer for Flutter apps: one place
/// for error handling (always throws [ApiException], never crashes), TTL
/// caching with force-refresh, polling streams, and file-based logging.

library;

export 'package:dio/dio.dart'
    show
        FormData,
        MultipartFile,
        CancelToken,
        ProgressCallback,
        Interceptor,
        InterceptorsWrapper;

export 'src/cache/cache_options.dart';
export 'src/cache/cache_store.dart';
export 'src/client/api_client_config.dart';
export 'src/client/smart_api_client.dart';
export 'src/exceptions/api_exception.dart';
export 'src/logging/api_logger.dart';
export 'src/response/api_response.dart';
export 'src/stream/api_stream_options.dart';

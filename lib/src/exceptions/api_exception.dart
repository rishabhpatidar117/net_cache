import '../response/api_response.dart';

/// The single exception type this package ever throws.
///
/// Every call site inside [SmartApiClient] wraps its work in one centralized
/// try/catch (see `_execute` in `smart_api_client.dart`), so callers never
/// need to guard against raw [DioException]s, [FormatException]s, socket
/// errors, etc. — they only ever need to catch [ApiException].
///
/// The original error (DioException, ApiResponse, Map, String, anything) is
/// kept in [source] and lazily turned into a human-readable [error] string
/// via [getErrorMessage] only when it's actually read, so building an
/// [ApiException] is always cheap even in hot paths (e.g. inside a polling
/// stream).
class ApiException implements Exception {
  ApiException(this.source);

  /// The original, unprocessed error. Useful if you need to branch on the
  /// underlying DioException type/status code rather than just show text.
  final dynamic source;

  /// Human-readable message, extracted from [source]. Safe to show directly
  /// in a SnackBar / dialog.
  String get error => getErrorMessage(source);

  /// Best-effort HTTP status code, if [source] came from a server response.
  int? get statusCode {
    final s = source;
    if (s is ApiResponse) return null;
    try {
      final response = (s as dynamic).response;
      final code = response?.statusCode;
      if (code is int) return code;
    } catch (_) {
      /* source has no `.response` (not a DioException) — fine, ignore. */
    }
    return null;
  }

  @override
  String toString() => error;
}

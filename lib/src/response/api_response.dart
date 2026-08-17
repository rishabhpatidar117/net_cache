import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../exceptions/api_exception.dart';
import '../logging/api_logger.dart';

/// Normalized wrapper around any API response, regardless of whether the
/// backend uses `{status: bool}`, `{success: bool}`, or just relies on the
/// HTTP status code to signal success.
class ApiResponse {
  final bool success;
  dynamic data;
  String message;
  dynamic completeData;

  /// True when this instance was served from the cache instead of a live
  /// network call. Useful for showing a "stale" indicator in the UI.
  final bool fromCache;

  ApiResponse({
    required this.success,
    this.data,
    required this.message,
    this.completeData,
    this.fromCache = false,
  });

  factory ApiResponse.fromResponse(Response response) {
    try {
      dynamic data = response.data;
      if (data is! Map && data is! String) {
        return ApiResponse(
          success:
              response.statusCode != null &&
              response.statusCode! >= 200 &&
              response.statusCode! < 300,
          data: data,
          message: (data is Map && data["message"] != null)
              ? (data["message"]?.toString() ?? 'Unknown error occurred.')
              : getErrorMessage(data),
          completeData: response.data,
        );
      }
      if (data is String) {
        data = data.trim().isEmpty ? <String, dynamic>{} : jsonDecode(data);
      }

      final success =
          ((data['status'] != null && data['status'] is bool)
              ? data['status']
              : (data['success'] != null && data['success'] is bool)
              ? data['success']
              : response.statusCode != null &&
                    response.statusCode! >= 200 &&
                    response.statusCode! < 300) ||
          response.statusCode == 201 ||
          response.statusCode == 202 ||
          response.statusCode == 203 ||
          response.statusCode == 204;

      return ApiResponse(
        success: success,
        data: data['data'] ?? data,
        message: (data['error'] ?? data['message'] ?? 'Unknown error occurred.')
            .toString(),
        completeData: response.data,
      );
    } catch (e) {
      ApiLogger.error('ApiResponse', 'fromResponse', '$e');
      throw ApiException(e.toString());
    }
  }

  /// Returns a copy of this response marked as [fromCache]. Used internally
  /// when a cache hit is served back to the caller.
  ApiResponse asCached() => ApiResponse(
    success: success,
    data: data,
    message: message,
    completeData: completeData,
    fromCache: true,
  );
}

/// Turns any error this package might encounter — a [DioException], a raw
/// [ApiResponse], a decoded JSON `Map`, or a plain `String` — into one clean,
/// user-facing message. Handles Laravel-style nested validation errors
/// (`{"errors": {"email": ["required", "invalid"]}}`) automatically.
String getErrorMessage(Object error) {
  if (error is ApiException) {
    return getErrorMessage(error.source);
  }
  if (error is Map) {
    final d = _extractErrorMessages(error);
    if (d.isNotEmpty) {
      return d.join(', ');
    }
  }
  if (error is ApiResponse) {
    if (error.message.trim().isNotEmpty) {
      return error.message;
    }
    final errorMessages = _extractErrorMessages(error.completeData);
    if (errorMessages.isNotEmpty) {
      return errorMessages.join('\n\u2022 ');
    }
  }

  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.cancel:
        return 'Request was canceled.';
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Request timed out. Please check your internet connection.';
      case DioExceptionType.badCertificate:
        return 'Invalid SSL certificate.';
      case DioExceptionType.connectionError:
        return 'No internet connection. Please try again.';
      case DioExceptionType.unknown:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.badResponse:
        final newError = error.error;
        if (newError is HttpException) {
          return newError.message;
        }
        final response = error.response;
        if (response == null) return 'Server error occurred. ${error.error}';

        dynamic data = response.data;
        if (data is String) {
          try {
            data = json.decode(data);
          } catch (_) {
            return data.trim().isNotEmpty ? data : 'An error occurred.';
          }
        }

        final errorMessages = _extractErrorMessages(data);
        if (errorMessages.isNotEmpty) {
          return errorMessages.join('\n\u2022 ');
        }
        return 'Error: ${response.statusCode}';
    }
  }

  return error.toString();
}

List<String> _extractErrorMessages(dynamic data) {
  final messages = <String>[];

  if (data is Map<String, dynamic>) {
    const errorKeys = ['errors', 'error', 'message', 'msg', 'detail'];

    for (final key in errorKeys) {
      if (data.containsKey(key)) {
        messages.addAll(_flattenErrors(data[key]));
      }
    }

    if (messages.isEmpty) {
      for (final entry in data.entries) {
        if (entry.key.toLowerCase().contains('error') ||
            entry.key.toLowerCase().contains('message') ||
            entry.key.toLowerCase().contains('invalid') ||
            entry.value is List ||
            entry.value is Map) {
          messages.addAll(_flattenErrors(entry.value));
        }
      }
    }
  } else if (data is List) {
    messages.addAll(_flattenErrors(data));
  } else if (data is String) {
    if (data.trim().isNotEmpty) messages.add(data.trim());
  }

  return messages
      .map((m) => m.trim())
      .where((m) => m.isNotEmpty)
      .toSet()
      .toList();
}

List<String> _flattenErrors(dynamic value) {
  final result = <String>[];

  if (value is String) {
    if (value.trim().isNotEmpty) result.add(value.trim());
  } else if (value is List) {
    for (final item in value) {
      result.addAll(_flattenErrors(item));
    }
  } else if (value is Map<String, dynamic>) {
    for (final entry in value.entries) {
      result.addAll(_flattenErrors(entry.value));
    }
  } else if (value != null) {
    final str = value.toString();
    if (str.trim().isNotEmpty) result.add(str.trim());
  }

  return result;
}

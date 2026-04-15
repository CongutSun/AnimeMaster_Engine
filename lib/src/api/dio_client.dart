import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final String path;

  ApiException({this.statusCode, required this.message, required this.path});

  @override
  String toString() =>
      'ApiException(code: $statusCode, path: $path, message: $message)';
}

class DioClient {
  static final DioClient _instance = DioClient._internal();
  factory DioClient() => _instance;

  static const int _timeoutSeconds = 10;
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static const Set<String> _proxyRetryHosts = <String>{
    'share.dmhy.org',
    'mikanani.me',
    'mikanime.tv',
  };

  late final Dio dio;

  DioClient._internal() {
    dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: _timeoutSeconds),
        receiveTimeout: const Duration(seconds: _timeoutSeconds),
        sendTimeout: const Duration(seconds: _timeoutSeconds),
        headers: const {'User-Agent': _userAgent},
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.next(options),
        onResponse: (response, handler) => handler.next(response),
        onError: (DioException error, handler) async {
          if (_shouldRetryViaProxy(error)) {
            try {
              final Uri originalUri = error.requestOptions.uri;
              final String proxyUrl =
                  'https://api.allorigins.win/raw?url=${Uri.encodeComponent(originalUri.toString())}';

              final Dio retryDio = Dio(
                BaseOptions(
                  connectTimeout: const Duration(seconds: 15),
                  receiveTimeout: const Duration(seconds: 15),
                  headers: const {'User-Agent': _userAgent},
                ),
              );

              final Response<dynamic> response = await retryDio.request(
                proxyUrl,
                options: Options(
                  method: error.requestOptions.method,
                  responseType: error.requestOptions.responseType,
                ),
                data: error.requestOptions.data,
                queryParameters: error.requestOptions.queryParameters,
              );

              debugPrint(
                '[DioClient] Proxy retry success for ${originalUri.host}',
              );
              return handler.resolve(response);
            } catch (retryError) {
              debugPrint(
                '[DioClient] Proxy retry failed for '
                '${error.requestOptions.uri}: $retryError',
              );
            }
          }

          final ApiException apiException = ApiException(
            statusCode: error.response?.statusCode,
            message: error.message ?? 'Unknown Network Error',
            path: error.requestOptions.uri.toString(),
          );

          return handler.next(error.copyWith(error: apiException));
        },
      ),
    );

    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(
          request: false,
          requestHeader: false,
          responseHeader: false,
          responseBody: false,
          error: true,
        ),
      );
    }
  }

  bool _shouldRetryViaProxy(DioException error) {
    final bool isNetworkError =
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.unknown;
    final Uri uri = error.requestOptions.uri;

    if (!isNetworkError || error.requestOptions.method.toUpperCase() != 'GET') {
      return false;
    }

    if (uri.host == 'api.allorigins.win') {
      return false;
    }

    return _proxyRetryHosts.contains(uri.host.toLowerCase());
  }
}

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

typedef AuthTokenProvider = Future<String?> Function();

class DioClient {
  static final DioClient _instance = DioClient._internal();
  factory DioClient() => _instance;

  /// Register a callback that returns a fresh Bangumi Bearer token
  /// when a 401 response is detected on api.bgm.tv endpoints.
  ///
  /// Set this once during app startup (e.g. from [SettingsProvider]).
  static AuthTokenProvider? _tokenRefresher;

  /// Must be called early (before any API call) to enable automatic
  /// 401 → token‑refresh → retry for Bangumi endpoints.
  static void setAuthTokenRefresher(AuthTokenProvider refresher) {
    _tokenRefresher = refresher;
  }

  static const int _timeoutSeconds = 20;
  static const int _maxBackoffRetries = 2;
  static const Duration _baseBackoffDelay = Duration(milliseconds: 350);
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static const Set<String> _authProtectedHosts = <String>{
    'api.bgm.tv',
    'bgm.tv',
    'chii.in',
  };
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
          // ── 401 token refresh for Bangumi auth-protected endpoints ──
          if (_shouldRefreshAuthToken(error)) {
            final int authAttempt =
                (error.requestOptions.extra['_authRetry'] as int?) ?? 0;
            if (authAttempt == 0) {
              error.requestOptions.extra['_authRetry'] = 1;
              try {
                final String? freshToken = await _tokenRefresher?.call();
                if (freshToken != null && freshToken.isNotEmpty) {
                  final Options patchedOptions = error.requestOptions.extra
                      .containsKey('_authRetry')
                      ? Options(
                          headers: <String, String>{
                            ...?error.requestOptions.headers,
                            'Authorization': 'Bearer $freshToken',
                          },
                        )
                      : Options();
                  final RequestOptions patched = error.requestOptions
                    ..headers['Authorization'] = 'Bearer $freshToken';
                  final Response<dynamic> response = await dio.fetch<dynamic>(
                    patched,
                  );
                  return handler.resolve(response);
                }
              } catch (retryError) {
                debugPrint(
                  '[DioClient] Auth token refresh/retry failed for '
                  '${error.requestOptions.uri}: $retryError',
                );
              }
            }
          }

          if (_shouldRetryWithBackoff(error)) {
            final int attempt =
                (error.requestOptions.extra['retryAttempt'] as int?) ?? 0;
            error.requestOptions.extra['retryAttempt'] = attempt + 1;
            await Future<void>.delayed(_retryDelay(attempt));
            try {
              final Response<dynamic> response = await dio.fetch<dynamic>(
                error.requestOptions,
              );
              return handler.resolve(response);
            } catch (retryError) {
              debugPrint(
                '[DioClient] Backoff retry failed for '
                '${error.requestOptions.uri}: $retryError',
              );
            }
          }

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

  bool _shouldRefreshAuthToken(DioException error) {
    if (_tokenRefresher == null) return false;
    final int? statusCode = error.response?.statusCode;
    if (statusCode != 401) return false;
    final String host = error.requestOptions.uri.host.toLowerCase();
    return _authProtectedHosts.contains(host);
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

  bool _shouldRetryWithBackoff(DioException error) {
    final int attempt =
        (error.requestOptions.extra['retryAttempt'] as int?) ?? 0;
    if (attempt >= _maxBackoffRetries) {
      return false;
    }

    final String method = error.requestOptions.method.toUpperCase();
    if (method != 'GET' && method != 'HEAD') {
      return false;
    }

    final Uri uri = error.requestOptions.uri;
    if (uri.host == 'api.allorigins.win') {
      return false;
    }

    final int? statusCode = error.response?.statusCode;
    if (statusCode != null && statusCode >= 500) {
      return true;
    }

    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.unknown;
  }

  Duration _retryDelay(int attempt) {
    return _baseBackoffDelay * (1 << attempt);
  }
}

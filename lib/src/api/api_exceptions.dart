/// Typed exceptions for Bangumi API operations.
///
/// Enables differentiated user-facing error messages instead of
/// generic "暂无数据" for every failure mode.
class NetworkException implements Exception {
  final String message;
  final Object? cause;
  const NetworkException(this.message, [this.cause]);

  @override
  String toString() => 'NetworkException: $message';
}

class ServerException implements Exception {
  final int? statusCode;
  final String endpoint;
  const ServerException(this.endpoint, [this.statusCode]);

  @override
  String toString() =>
      'ServerException(endpoint: $endpoint, status: ${statusCode ?? "unknown"})';
}

class ApiRateLimitException implements Exception {
  final int? retryAfterSeconds;
  const ApiRateLimitException([this.retryAfterSeconds]);

  @override
  String toString() =>
      'ApiRateLimitException(retryAfter: ${retryAfterSeconds ?? "unknown"}s)';
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => 'AuthException: $message';
}

class EmptyResultException implements Exception {
  final String endpoint;
  const EmptyResultException(this.endpoint);

  @override
  String toString() => 'EmptyResultException($endpoint)';
}

/// Returns a user-friendly Chinese message for a given exception.
String exceptionUserMessage(Object exception) {
  return switch (exception) {
    NetworkException() => '网络连接异常，请检查网络后重试',
    ServerException(:final int? statusCode) =>
      '服务器错误（${statusCode ?? "未知"}），请稍后重试',
    ApiRateLimitException() => '请求过于频繁，请稍后重试',
    AuthException() => '认证已过期，请重新登录',
    EmptyResultException() => '暂无数据',
    _ => '数据加载失败，请下拉重试或检查网络状态',
  };
}

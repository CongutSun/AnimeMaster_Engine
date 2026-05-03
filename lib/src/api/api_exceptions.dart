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

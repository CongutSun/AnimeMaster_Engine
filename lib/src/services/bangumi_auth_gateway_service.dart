import 'package:dio/dio.dart';

import '../models/bangumi_auth_gateway_models.dart';

class BangumiAuthGatewayService {
  final String baseUrl;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 45),
      receiveTimeout: const Duration(seconds: 45),
      sendTimeout: const Duration(seconds: 45),
      responseType: ResponseType.json,
    ),
  );

  BangumiAuthGatewayService({required this.baseUrl});

  String get _normalizedBaseUrl => baseUrl.trim().replaceAll(RegExp(r'/$'), '');

  Future<BangumiAuthStartResponse> startAuthorization({
    required String callbackScheme,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '$_normalizedBaseUrl/auth/bangumi/mobile/start',
      queryParameters: <String, String>{'callback_scheme': callbackScheme},
    );
    final dynamic data = response.data;
    if (response.statusCode != 200 || data is! Map<String, dynamic>) {
      throw Exception('Bangumi 授权网关未返回有效的授权地址。');
    }
    final BangumiAuthStartResponse result = BangumiAuthStartResponse.fromJson(
      data,
    );
    if (result.requestId.isEmpty || result.authorizationUrl.isEmpty) {
      throw Exception('Bangumi 授权网关返回的数据不完整。');
    }
    return result;
  }

  Future<BangumiGatewaySession> fetchSession(String sessionId) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '$_normalizedBaseUrl/auth/bangumi/mobile/session',
      queryParameters: <String, String>{'session_id': sessionId},
    );
    return _parseSessionResponse(response, 'Bangumi 会话换取失败。');
  }

  Future<BangumiGatewaySession> refreshSession(String sessionId) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '$_normalizedBaseUrl/auth/bangumi/mobile/refresh',
      data: <String, String>{'session_id': sessionId},
      options: Options(contentType: Headers.jsonContentType),
    );
    return _parseSessionResponse(response, 'Bangumi 会话刷新失败。');
  }

  Future<void> logout(String sessionId) async {
    await _dio.post<dynamic>(
      '$_normalizedBaseUrl/auth/bangumi/mobile/logout',
      data: <String, String>{'session_id': sessionId},
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  BangumiGatewaySession _parseSessionResponse(
    Response<dynamic> response,
    String fallbackError,
  ) {
    final dynamic data = response.data;
    if (response.statusCode != 200 || data is! Map<String, dynamic>) {
      throw Exception(fallbackError);
    }
    final BangumiGatewaySession session = BangumiGatewaySession.fromJson(data);
    if (session.sessionId.isEmpty || session.accessToken.isEmpty) {
      throw Exception(fallbackError);
    }
    return session;
  }
}

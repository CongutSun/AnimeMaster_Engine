import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../models/bangumi_auth_gateway_models.dart';

class BangumiLoginProof {
  BangumiLoginProof() : verifier = _newVerifier();

  final String verifier;
  String get challenge => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');

  static String _newVerifier() {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }
}

class BangumiAuthGatewayService {
  final String baseUrl;
  final Dio _dio;

  BangumiAuthGatewayService({required this.baseUrl, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              followRedirects: false,
              connectTimeout: const Duration(seconds: 45),
              receiveTimeout: const Duration(seconds: 45),
              sendTimeout: const Duration(seconds: 45),
            ),
          );

  String get _normalizedBaseUrl {
    final address = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(address);
    final loopback =
        uri != null &&
        uri.scheme == 'http' &&
        {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' && !loopback)) {
      throw const FormatException('Bangumi 登录网关需要 HTTPS 地址。');
    }
    return address;
  }

  Future<BangumiAuthStartResponse> startAuthorization({
    required String callbackScheme,
    required BangumiLoginProof proof,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '$_normalizedBaseUrl/auth/bangumi/mobile/start',
      queryParameters: <String, String>{
        'callback_scheme': callbackScheme,
        'code_challenge_method': 'S256',
        'code_challenge': proof.challenge,
      },
    );
    final dynamic data = response.data;
    if (response.statusCode != 200 || data is! Map<String, dynamic>) {
      throw Exception('Bangumi 授权网关未返回有效的授权地址。');
    }
    if (data['code_challenge_method'] != 'S256') {
      throw Exception('Bangumi 授权网关需要升级才能安全登录。');
    }
    final BangumiAuthStartResponse result = BangumiAuthStartResponse.fromJson(
      data,
    );
    if (result.requestId.isEmpty || result.authorizationUrl.isEmpty) {
      throw Exception('Bangumi 授权网关返回的数据不完整。');
    }
    return result;
  }

  Future<BangumiGatewaySession> fetchSession(
    String sessionId, {
    required BangumiLoginProof proof,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '$_normalizedBaseUrl/auth/bangumi/mobile/session',
      data: <String, String>{
        'session_id': sessionId,
        'code_verifier': proof.verifier,
      },
      options: Options(
        contentType: Headers.jsonContentType,
        followRedirects: false,
      ),
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

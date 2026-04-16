import 'dart:math';

import 'package:dio/dio.dart';

import '../api/dio_client.dart';
import '../models/bangumi_oauth_token.dart';
import '../models/bangumi_user_profile.dart';

class BangumiOAuthService {
  static const String callbackScheme = 'animemasteroauth';
  static const String redirectUri = '$callbackScheme://callback';

  final Dio _dio = DioClient().dio;

  String createState({int length = 24}) {
    const String alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final Random random = Random.secure();
    return List<String>.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  String buildAuthorizationUrl({
    required String clientId,
    required String state,
  }) {
    return Uri.https('bgm.tv', '/oauth/authorize', <String, String>{
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'state': state,
    }).toString();
  }

  Future<BangumiOAuthToken> exchangeCode({
    required String clientId,
    required String clientSecret,
    required String code,
    required String state,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      'https://bgm.tv/oauth/access_token',
      data: <String, String>{
        'grant_type': 'authorization_code',
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': code,
        'redirect_uri': redirectUri,
        'state': state,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
        headers: const <String, String>{'Accept': 'application/json'},
      ),
    );

    final dynamic data = response.data;
    if (response.statusCode != 200 || data is! Map<String, dynamic>) {
      throw Exception('Bangumi 授权换取令牌失败。');
    }

    final BangumiOAuthToken token = BangumiOAuthToken.fromJson(data);
    if (token.accessToken.isEmpty || token.userId.isEmpty) {
      throw Exception('Bangumi 返回的授权信息不完整。');
    }
    return token;
  }

  Future<BangumiOAuthToken> refreshAccessToken({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      'https://bgm.tv/oauth/access_token',
      data: <String, String>{
        'grant_type': 'refresh_token',
        'client_id': clientId,
        'client_secret': clientSecret,
        'refresh_token': refreshToken,
        'redirect_uri': redirectUri,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
        headers: const <String, String>{'Accept': 'application/json'},
      ),
    );

    final dynamic data = response.data;
    if (response.statusCode != 200 || data is! Map<String, dynamic>) {
      throw Exception('Bangumi 刷新令牌失败。');
    }

    final BangumiOAuthToken token = BangumiOAuthToken.fromJson(data);
    if (token.accessToken.isEmpty) {
      throw Exception('Bangumi 刷新后的令牌无效。');
    }
    return token;
  }

  Future<BangumiUserProfile> fetchCurrentUserProfile(String accessToken) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      'https://api.bgm.tv/v0/me',
      options: Options(
        responseType: ResponseType.json,
        headers: <String, String>{
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      ),
    );

    final dynamic data = response.data;
    if (response.statusCode != 200 || data is! Map<String, dynamic>) {
      throw Exception('Bangumi 用户资料拉取失败。');
    }

    final BangumiUserProfile profile = BangumiUserProfile.fromJson(data);
    if (profile.username.isEmpty && profile.nickname.isEmpty) {
      throw Exception('Bangumi 返回的用户资料不完整。');
    }
    return profile;
  }
}

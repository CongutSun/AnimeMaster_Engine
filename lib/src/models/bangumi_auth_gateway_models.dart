import 'bangumi_user_profile.dart';

class BangumiAuthStartResponse {
  final String requestId;
  final String authorizationUrl;

  const BangumiAuthStartResponse({
    required this.requestId,
    required this.authorizationUrl,
  });

  factory BangumiAuthStartResponse.fromJson(Map<String, dynamic> json) {
    return BangumiAuthStartResponse(
      requestId: json['request_id']?.toString().trim() ?? '',
      authorizationUrl: json['authorization_url']?.toString().trim() ?? '',
    );
  }
}

class BangumiGatewaySession {
  final String sessionId;
  final String accessToken;
  final DateTime? expiresAt;
  final BangumiUserProfile profile;

  const BangumiGatewaySession({
    required this.sessionId,
    required this.accessToken,
    required this.expiresAt,
    required this.profile,
  });

  factory BangumiGatewaySession.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> profileJson = json['profile'] is Map
        ? Map<String, dynamic>.from(json['profile'] as Map)
        : <String, dynamic>{};
    return BangumiGatewaySession(
      sessionId: json['session_id']?.toString().trim() ?? '',
      accessToken: json['access_token']?.toString().trim() ?? '',
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      profile: BangumiUserProfile.fromJson(profileJson),
    );
  }
}

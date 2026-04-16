class BangumiOAuthToken {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final String userId;

  const BangumiOAuthToken({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.userId,
  });

  factory BangumiOAuthToken.fromJson(Map<String, dynamic> json) {
    return BangumiOAuthToken(
      accessToken: json['access_token']?.toString() ?? '',
      refreshToken: json['refresh_token']?.toString() ?? '',
      expiresIn: int.tryParse(json['expires_in']?.toString() ?? '') ?? 0,
      userId: json['user_id']?.toString() ?? '',
    );
  }

  DateTime expiresAtFrom(DateTime issuedAt) {
    return issuedAt.add(Duration(seconds: expiresIn));
  }
}

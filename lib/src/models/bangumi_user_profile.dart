class BangumiUserProfile {
  final String username;
  final String nickname;
  final String avatarLarge;
  final String avatarMedium;
  final String sign;

  const BangumiUserProfile({
    required this.username,
    required this.nickname,
    required this.avatarLarge,
    required this.avatarMedium,
    required this.sign,
  });

  factory BangumiUserProfile.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> avatar = json['avatar'] is Map
        ? Map<String, dynamic>.from(json['avatar'] as Map)
        : <String, dynamic>{};
    return BangumiUserProfile(
      username: json['username']?.toString().trim() ?? '',
      nickname: json['nickname']?.toString().trim() ?? '',
      avatarLarge: avatar['large']?.toString().trim() ?? '',
      avatarMedium: avatar['medium']?.toString().trim() ?? '',
      sign: json['sign']?.toString().trim() ?? '',
    );
  }

  String get displayName => nickname.isNotEmpty ? nickname : username;

  String get avatarUrl => avatarLarge.isNotEmpty ? avatarLarge : avatarMedium;
}

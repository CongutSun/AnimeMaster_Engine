class Anime {
  final int id;
  final String name;      // 原名
  final String nameCn;    // 中文名
  final String imageUrl;  // 封面图
  final String score;     // 评分
  final int eps;          // 总集数
  final int epStatus;     // 观看进度(追番库使用)

  Anime({
    required this.id,
    required this.name,
    this.nameCn = '',
    this.imageUrl = '',
    this.score = '',
    this.eps = 0,
    this.epStatus = 0,
  });

  factory Anime.fromJson(Map<String, dynamic> json) {
    // 兼容普通 API 和个人收藏 API (收藏 API 的实体在 'subject' 字段里)
    final subject = json['subject'] ?? json;

    final id = subject['id'] is int ? subject['id'] : int.tryParse(subject['id']?.toString() ?? '') ?? 0;
    final name = subject['name']?.toString() ?? '';
    final nameCn = subject['name_cn']?.toString() ?? '';
    
    // 安全解析图片 URL
    String imageUrl = '';
    if (subject['images'] != null && subject['images']['large'] != null) {
      imageUrl = subject['images']['large'].toString();
      // 统一替换为 https
      if (imageUrl.startsWith('http://')) {
        imageUrl = imageUrl.replaceFirst('http://', 'https://');
      } else if (imageUrl.startsWith('//')) {
        imageUrl = 'https:$imageUrl';
      }
    }

    // 安全解析评分
    String score = '';
    if (subject['rating'] != null && subject['rating']['score'] != null) {
      score = subject['rating']['score'].toString();
    }

    final eps = subject['eps'] is int ? subject['eps'] : int.tryParse(subject['eps']?.toString() ?? '') ?? 0;
    final epStatus = json['ep_status'] is int ? json['ep_status'] : 0;

    return Anime(
      id: id,
      name: name,
      nameCn: nameCn,
      imageUrl: imageUrl,
      score: score,
      eps: eps,
      epStatus: epStatus,
    );
  }

  // 辅助 Getter：优先返回中文名，没有则返回原名
  String get displayName => nameCn.isNotEmpty ? nameCn : name;
}
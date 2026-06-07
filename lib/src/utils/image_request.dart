import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../config/bangumi_gateway_config.dart';

// 专业级：配置单例模式的自定义缓存管理器，控制最大并发与缓存时间，防止 OOM 与文件系统占用过高
class AppImageCacheManager {
  static const String key = 'anime_image_cache';

  static CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 7), // 缓存保留 7 天
      maxNrOfCacheObjects: 300, // 最大缓存条目数，避免占用过多手机存储
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: HttpFileService(),
    ),
  );
}

String normalizeImageUrl(String url) {
  final String normalized = BangumiGatewayConfig.normalizeBangumiUrl(url);
  return BangumiGatewayConfig.imageProxyUrl(normalized);
}

Map<String, String> buildImageHeaders(String imageUrl) {
  final normalized = BangumiGatewayConfig.normalizeBangumiUrl(imageUrl);
  final referer = normalized.contains('chii.in')
      ? 'https://chii.in/'
      : 'https://bgm.tv/';

  return {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': referer,
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
    'Connection': 'keep-alive',
  };
}

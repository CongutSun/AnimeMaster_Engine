import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart'; 
import '../models/anime.dart';
import '../screens/detail_page.dart';
import '../utils/image_request.dart';

class AnimeCard extends StatelessWidget {
  final Anime anime;
  final bool isTop;

  const AnimeCard({super.key, required this.anime, this.isTop = false});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final placeholderColor = isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200;
    final displayName = anime.nameCn.isNotEmpty ? anime.nameCn : anime.name;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DetailPage(
              animeId: anime.id,
              initialName: displayName,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1), 
                    blurRadius: 4, 
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: normalizeImageUrl(anime.imageUrl),
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 300),
                  httpHeaders: buildImageHeaders(anime.imageUrl), 
                  // 注入我们自定义的 CacheManager，保障 Release 下稳定加载
                  cacheManager: AppImageCacheManager.instance,
                  
                  placeholder: (context, url) => Container(
                    color: placeholderColor,
                    child: const Center(
                      child: Icon(Icons.image_outlined, color: Colors.grey, size: 24),
                    ),
                  ),
                  
                  errorWidget: (context, url, error) => Container(
                    color: placeholderColor,
                    child: const Center(
                      child: Icon(Icons.broken_image_outlined, color: Colors.grey, size: 24),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 优化：不再使用写死的固定高度（之前的 64 或 46），而是根据内容自适应包裹，使用 Flexible 兜底防止溢出
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              if (isTop && anime.score.isNotEmpty)
                Row(
                  children: [
                    const Icon(Icons.star, size: 12, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      anime.score,
                      style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold),
                    ),
                  ],
                )
              else
                Text(
                  anime.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
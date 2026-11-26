import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/anime.dart';
import '../screens/detail_page.dart';
import '../utils/image_request.dart';

class AnimeCard extends StatelessWidget {
  final Anime anime;
  final bool isTop;

  final VoidCallback? onTap;
  const AnimeCard({
    super.key,
    required this.anime,
    this.isTop = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDarkMode = theme.brightness == Brightness.dark;
    final Color placeholderColor = isDarkMode
        ? colors.surfaceContainerHighest
        : const Color(0xFFE9E9EE);
    final String displayName = anime.nameCn.isNotEmpty
        ? anime.nameCn
        : anime.name;

    return Semantics(
      label: displayName,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap:
              onTap ??
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        DetailPage(animeId: anime.id, initialName: displayName),
                  ),
                );
              },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: normalizeImageUrl(anime.imageUrl),
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 260),
                    httpHeaders: buildImageHeaders(anime.imageUrl),
                    cacheManager: AppImageCacheManager.instance,
                    placeholder: (context, url) => Container(
                      color: placeholderColor,
                      child: Center(
                        child: Icon(
                          Icons.image_outlined,
                          color: colors.onSurfaceVariant,
                          size: 24,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: placeholderColor,
                      child: Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: colors.onSurfaceVariant,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 4),
              if (isTop && anime.score.isNotEmpty)
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.star_rounded,
                      size: 13,
                      color: Color(0xFFFF9F0A),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      anime.score,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFFFF9F0A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              else if (anime.name.isNotEmpty && anime.name != displayName)
                Text(
                  anime.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

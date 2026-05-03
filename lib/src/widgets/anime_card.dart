import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/anime.dart';
import '../screens/detail_page.dart';
import '../utils/image_request.dart';

class AnimeCard extends StatelessWidget {
  final Anime anime;
  final bool isTop;

  const AnimeCard({super.key, required this.anime, this.isTop = false});

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
          onTap: () {
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
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.outlineVariant),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDarkMode ? 0.36 : 0.14,
                      ),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
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
            ),
            const SizedBox(height: 9),
            Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.12,
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
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              )
            else
              Text(
                anime.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
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

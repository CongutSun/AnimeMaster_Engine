import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../utils/app_strings.dart';
import 'anime_card.dart';

class AnimeGrid extends StatelessWidget {
  final List<Anime> animeList;
  final bool isTop;

  const AnimeGrid({super.key, required this.animeList, this.isTop = false});

  @override
  Widget build(BuildContext context) {
    if (animeList.isEmpty) {
      return const Text(
        AppStrings.noData,
        style: TextStyle(color: Colors.grey),
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final scale = MediaQuery.textScalerOf(context);
        final minWidth = 108 * (scale.scale(16) / 16).clamp(1.0, 2.0);
        final crossAxisCount = ((width + 12) / (minWidth + 12)).floor().clamp(
          1,
          8,
        );
        final tileWidth = (width - (crossAxisCount - 1) * 12) / crossAxisCount;
        final textHeight =
            scale.scale(16) * 1.35 * 2 + scale.scale(14) * 1.45 + 20;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisExtent: tileWidth * 1.5 + textHeight,
            crossAxisSpacing: 12,
            mainAxisSpacing: 20,
          ),
          itemCount: animeList.length,
          itemBuilder: (context, index) {
            final anime = animeList[index];
            return AnimeCard(anime: anime, isTop: isTop);
          },
        );
      },
    );
  }
}

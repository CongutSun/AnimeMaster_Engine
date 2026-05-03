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
      return const Text(AppStrings.noData, style: TextStyle(color: Colors.grey));
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final int crossAxisCount = width >= 1180
            ? 8
            : width >= 980
            ? 7
            : width >= 760
            ? 5
            : width >= 480
            ? 4
            : 3;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.55,
            crossAxisSpacing: 14,
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

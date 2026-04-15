import 'package:flutter/material.dart';
import '../models/anime.dart';
import 'anime_card.dart';

class AnimeGrid extends StatelessWidget {
  final List<Anime> animeList;
  final bool isTop;

  const AnimeGrid({super.key, required this.animeList, this.isTop = false});

  @override
  Widget build(BuildContext context) {
    if (animeList.isEmpty) {
      return const Text('暂无数据', style: TextStyle(color: Colors.grey));
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.55, 
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: animeList.length,
      itemBuilder: (context, index) {
        final anime = animeList[index];
        // ✨ 修复：直接把整个 anime 对象传给卡片
        return AnimeCard(anime: anime, isTop: isTop);
      },
    );
  }
}
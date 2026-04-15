import 'package:flutter/material.dart';
import '../api/bangumi_api.dart';
import '../models/anime.dart';
import '../widgets/anime_grid.dart';

class RoleSubjectsPage extends StatefulWidget {
  final int id;
  final String name;
  final bool isCharacter;

  const RoleSubjectsPage({
    super.key,
    required this.id,
    required this.name,
    required this.isCharacter,
  });

  @override
  State<RoleSubjectsPage> createState() => _RoleSubjectsPageState();
}

class _RoleSubjectsPageState extends State<RoleSubjectsPage> {
  List<Anime> subjects = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final List<dynamic> data = widget.isCharacter
          ? await BangumiApi.getCharacterSubjects(widget.id)
          : await BangumiApi.getPersonSubjects(widget.id);

      if (!mounted) return;

      List<Anime> parsedAnime = [];
      for (var item in data) {
        if (item is Map) {
          // 兼容 v0 API 中关于图片的直接返回字段 'image' 或内嵌结构 'images'
          String imageUrl = '';
          if (item['image'] != null && item['image'] is String) {
            imageUrl = item['image'].toString();
          } else if (item['images'] is Map && item['images']['large'] != null) {
            imageUrl = item['images']['large'].toString();
          }

          if (imageUrl.startsWith('http://')) {
            imageUrl = imageUrl.replaceFirst('http://', 'https://');
          } else if (imageUrl.startsWith('//')) {
            imageUrl = 'https:$imageUrl';
          }

          parsedAnime.add(Anime(
            id: item['id'] is int ? item['id'] : int.tryParse(item['id']?.toString() ?? '') ?? 0,
            name: item['name']?.toString() ?? '',
            nameCn: item['name_cn']?.toString() ?? '',
            imageUrl: imageUrl,
            // 如果 API 带有职位或角色关系信息，也可以在此扩展
            score: item['staff']?.toString() ?? '', 
          ));
        }
      }

      setState(() {
        subjects = parsedAnime;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorMessage = '加载失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.isCharacter ? "角色" : "人物"}: ${widget.name}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(errorMessage!, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('重试'),
            )
          ],
        ),
      );
    }

    if (subjects.isEmpty) {
      return const Center(
        child: Text('暂无相关作品记录', style: TextStyle(color: Colors.grey)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub, color: Colors.blueAccent),
              const SizedBox(width: 8),
              Text(
                '共 ${subjects.length} 部参演/制作作品',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimeGrid(animeList: subjects, isTop: false),
        ],
      ),
    );
  }
}
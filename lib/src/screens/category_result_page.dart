import 'package:flutter/material.dart';
import '../api/bangumi_api.dart';
import '../models/anime.dart';
import '../widgets/anime_grid.dart';

class CategoryResultPage extends StatefulWidget {
  final String title;
  final String searchMode;
  final Object query; // 修复点：移除 dynamic，明确声明类型约束
  final int searchType;

  const CategoryResultPage({
    super.key,
    required this.title,
    required this.searchMode,
    required this.query,
    this.searchType = 2,
  });

  @override
  State<CategoryResultPage> createState() => _CategoryResultPageState();
}

class _CategoryResultPageState extends State<CategoryResultPage> {
  List<Anime> searchResults = [];
  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = true;
  int currentPage = 1;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchData();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        if (!isLoading && !isLoadingMore && hasMore) {
          _fetchData(isLoadMore: true);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchData({bool isLoadMore = false}) async {
    if (isLoadMore) {
      setState(() => isLoadingMore = true);
    } else {
      setState(() => isLoading = true);
    }

    List<dynamic> rawData = [];
    try {
      if (widget.searchMode == 'tag') {
        rawData = await BangumiApi.getSubjectsByTag(
          widget.query.toString(),
          type: widget.searchType,
          page: currentPage,
        );
        if (rawData.isEmpty || rawData.length < 24) hasMore = false;
      } else if (widget.searchMode == 'character') {
        if (currentPage == 1) {
          final qId = int.tryParse(widget.query.toString()) ?? 0;
          rawData = await BangumiApi.getCharacterSubjects(qId);
        }
        hasMore = false;
      } else if (widget.searchMode == 'person') {
        if (currentPage == 1) {
          final qId = int.tryParse(widget.query.toString()) ?? 0;
          rawData = await BangumiApi.getPersonSubjects(qId);
        }
        hasMore = false;
      } else {
        if (currentPage == 1) {
          rawData = await BangumiApi.search(
            widget.query.toString(),
            type: widget.searchType,
          );
        }
        hasMore = false;
      }
    } catch (e) {
      hasMore = false;
    }

    List<Anime> newItems = rawData.whereType<Map>().map((e) {
      Map<String, dynamic> data = Map<String, dynamic>.from(e);
      if (data['image'] != null && data['images'] == null) {
        data['images'] = {'large': data['image']};
      }
      return Anime.fromJson(data);
    }).toList();

    if (mounted) {
      setState(() {
        searchResults.addAll(newItems);
        isLoading = false;
        isLoadingMore = false;
        currentPage++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 1,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : searchResults.isEmpty
          ? _buildEmptyState()
          : SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      '相关的系统归档数据：',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ),
                  AnimeGrid(animeList: searchResults, isTop: false),
                  if (isLoadingMore)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (!hasMore &&
                      searchResults.isNotEmpty &&
                      widget.searchMode == 'tag')
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(
                        child: Text(
                          '没有更多相关记录',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: Theme.of(context).dividerColor,
          ),
          const SizedBox(height: 16),
          const Text(
            '未能在当前分类下检索到相关记录',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

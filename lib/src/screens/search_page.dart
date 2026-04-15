import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/bangumi_api.dart';
import '../utils/image_request.dart';
import '../models/anime.dart';
import 'detail_page.dart';

class SearchPage extends StatefulWidget {
  final String keyword;

  const SearchPage({super.key, required this.keyword});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  List<Anime> searchResults = [];
  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = true;

  int currentSubjectType = 2; 
  int currentStart = 0;
  final int maxResults = 25; 

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _performSearch();
    
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    setState(() {
      isLoading = true;
      currentStart = 0;
      hasMore = true;
      searchResults.clear();
    });

    final rawResults = await BangumiApi.search(
      widget.keyword, 
      type: currentSubjectType, 
      start: currentStart, 
      maxResults: maxResults
    );

    if (mounted) {
      setState(() {
        searchResults = rawResults.map((e) => Anime.fromJson(e)).toList();
        isLoading = false;
        if (rawResults.length < maxResults) {
          hasMore = false;
        }
      });
    }
  }

  Future<void> _loadMore() async {
    if (isLoading || isLoadingMore || !hasMore) return;

    setState(() => isLoadingMore = true);
    currentStart += maxResults;

    final rawResults = await BangumiApi.search(
      widget.keyword, 
      type: currentSubjectType, 
      start: currentStart, 
      maxResults: maxResults
    );

    if (mounted) {
      setState(() {
        if (rawResults.isEmpty) {
          hasMore = false;
        } else {
          searchResults.addAll(rawResults.map((e) => Anime.fromJson(e)).toList());
          if (rawResults.length < maxResults) {
            hasMore = false;
          }
        }
        isLoadingMore = false;
      });
    }
  }

  Widget _buildProgressIndicator() {
    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (!hasMore && searchResults.isNotEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: Text('没有更多搜索结果了', style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('搜索: ${widget.keyword}', style: const TextStyle(fontSize: 16)),
        elevation: 1, 
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ToggleButtons(
              constraints: const BoxConstraints(minHeight: 32, minWidth: 60),
              borderRadius: BorderRadius.circular(8),
              isSelected: [currentSubjectType == 2, currentSubjectType == 1],
              onPressed: (index) {
                if (isLoading) return; 
                setState(() => currentSubjectType = index == 0 ? 2 : 1);
                _performSearch();
              },
              children: const [
                Text('番剧', style: TextStyle(fontSize: 13)), 
                Text('书籍', style: TextStyle(fontSize: 13))
              ],
            ),
          )
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : searchResults.isEmpty
              ? Center(
                  child: Text(
                    currentSubjectType == 2 ? '未找到相关番剧\n请尝试更换搜索词' : '未找到相关书籍\n请尝试更换搜索词',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16.0),
                  itemCount: searchResults.length + 1,
                  itemBuilder: (context, index) {
                    if (index == searchResults.length) {
                      return _buildProgressIndicator();
                    }
                    final anime = searchResults[index];
                    final String secureUrl = normalizeImageUrl(anime.imageUrl);
                    
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                      leading: secureUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: CachedNetworkImage(
                                imageUrl: secureUrl,
                                width: 50,
                                height: 70,
                                fit: BoxFit.cover,
                                httpHeaders: buildImageHeaders(secureUrl),
                                placeholder: (context, url) => Container(width: 50, height: 70, color: Colors.grey.withValues(alpha: 0.2)),
                                errorWidget: (context, url, error) => Container(width: 50, height: 70, color: Colors.grey.withValues(alpha: 0.2), child: const Icon(Icons.broken_image, color: Colors.grey)),
                              ),
                            )
                          : Container(width: 50, height: 70, color: Colors.grey.withValues(alpha: 0.2), child: const Icon(Icons.image_not_supported, color: Colors.grey)),
                      title: Text(anime.displayName, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(anime.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => DetailPage(
                          animeId: anime.id, 
                          initialName: anime.displayName,
                          subjectType: currentSubjectType,
                        )));
                      },
                    );
                  },
                ),
    );
  }
}
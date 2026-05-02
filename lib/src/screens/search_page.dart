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
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
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
      maxResults: maxResults,
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
      maxResults: maxResults,
    );

    if (mounted) {
      setState(() {
        if (rawResults.isEmpty) {
          hasMore = false;
        } else {
          searchResults.addAll(
            rawResults.map((e) => Anime.fromJson(e)).toList(),
          );
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
        title: Text(
          '搜索: ${widget.keyword}',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(
                  value: 2,
                  icon: Icon(Icons.tv_rounded, size: 16),
                  label: Text('番剧'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  icon: Icon(Icons.menu_book_rounded, size: 16),
                  label: Text('书籍'),
                ),
              ],
              selected: <int>{currentSubjectType},
              onSelectionChanged: (Set<int> value) {
                if (isLoading) return;
                setState(() => currentSubjectType = value.first);
                _performSearch();
              },
            ),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : searchResults.isEmpty
          ? Center(
              child: Text(
                currentSubjectType == 2
                    ? '未找到相关番剧\n请尝试更换搜索词'
                    : '未找到相关书籍\n请尝试更换搜索词',
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

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    leading: secureUrl.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              imageUrl: secureUrl,
                              width: 50,
                              height: 70,
                              fit: BoxFit.cover,
                              httpHeaders: buildImageHeaders(secureUrl),
                              placeholder: (context, url) => Container(
                                width: 50,
                                height: 70,
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                              ),
                              errorWidget: (context, url, error) => Container(
                                width: 50,
                                height: 70,
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                child: const Icon(
                                  Icons.broken_image,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            width: 50,
                            height: 70,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.image_not_supported,
                              color: Colors.grey,
                            ),
                          ),
                    title: Text(
                      anime.displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      anime.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DetailPage(
                            animeId: anime.id,
                            initialName: anime.displayName,
                            subjectType: currentSubjectType,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

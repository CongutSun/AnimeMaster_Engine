import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/anime.dart';
import '../utils/haptic_helper.dart';
import '../viewmodels/search_view_model.dart';
import '../utils/image_request.dart';
import '../widgets/skeleton.dart';
import 'detail_page.dart';

class SearchPage extends StatefulWidget {
  final String keyword;

  const SearchPage({super.key, required this.keyword});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final SearchViewModel _viewModel;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _viewModel = SearchViewModel();
    _viewModel.search(widget.keyword);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _viewModel.loadMore(widget.keyword);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _switchSubjectType(int type) {
    if (type == _viewModel.state.currentSubjectType) {
      return;
    }
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _viewModel.setSubjectType(type);
    _viewModel.search(widget.keyword);
  }

  Widget _buildProgressIndicator(SearchViewState state) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!state.hasMore && state.results.isNotEmpty) {
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
            child: AnimatedBuilder(
              animation: _viewModel,
              builder: (BuildContext context, Widget? child) {
                return SegmentedButton<int>(
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
                  selected: <int>{_viewModel.state.currentSubjectType},
                  onSelectionChanged: (Set<int> value) =>
                      _switchSubjectType(value.first),
                );
              },
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _viewModel,
        builder: (BuildContext context, Widget? child) {
          final SearchViewState state = _viewModel.state;

          if (state.isLoading) {
            return const Center(child: SkeletonBlock(width: 200, height: 32));
          }

          if (state.errorMessage != null && state.results.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      state.errorMessage!,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _viewModel.search(widget.keyword),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (state.results.isEmpty) {
            return Center(
              child: Text(
                state.currentSubjectType == 2
                    ? '未找到相关番剧\n请尝试更换搜索词'
                    : '未找到相关书籍\n请尝试更换搜索词',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16.0),
            itemCount: state.results.length + 1,
            itemBuilder: (BuildContext context, int index) {
              if (index == state.results.length) {
                return _buildProgressIndicator(state);
              }
              final Anime anime = state.results[index];
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (anime.score.isNotEmpty && anime.score != '暂无数据')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9F0A).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(Icons.star_rounded, size: 13, color: Color(0xFFFF9F0A)),
                              const SizedBox(width: 3),
                              Text(
                                anime.score,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFF9F0A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                  onTap: () {
                    maybeHaptic(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (BuildContext context) => DetailPage(
                          animeId: anime.id,
                          initialName: anime.displayName,
                          subjectType: state.currentSubjectType,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

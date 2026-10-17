import 'package:flutter/material.dart';

import '../models/online_episode_source.dart';
import '../repositories/bilibili_episode_mapping_repository.dart';
import '../services/bilibili_auth_service.dart';
import '../services/bilibili_video_service.dart';
import '../services/rss_feed_service.dart';
import 'bilibili_video_page.dart';
import 'download_center_page.dart';
import 'magnet_config_page.dart';

class ResourceSearchPage extends StatefulWidget {
  final String animeName;
  final List<String> aliases;
  final int bangumiSubjectId;
  final OnlineEpisodeQuery? episodeQuery;
  final BilibiliVideoService? bilibiliService;
  final BilibiliAuthService? bilibiliAuth;
  final BilibiliEpisodeMappingRepository? bilibiliMappings;
  final RssFeedService? feedService;

  const ResourceSearchPage({
    super.key,
    required this.animeName,
    required this.aliases,
    required this.bangumiSubjectId,
    this.episodeQuery,
    this.bilibiliService,
    this.bilibiliAuth,
    this.bilibiliMappings,
    this.feedService,
  });

  @override
  State<ResourceSearchPage> createState() => _ResourceSearchPageState();
}

class _ResourceSearchPageState extends State<ResourceSearchPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  int _index = 0;
  bool _websitesVisited = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    FocusScope.of(context).unfocus();
    setState(() {
      _index = index;
      if (index == 1) _websitesVisited = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final OnlineEpisodeQuery? query = widget.episodeQuery;
    final String heading = query == null || query.episodeLabel.isEmpty
        ? widget.animeName
        : '${widget.animeName} · ${query.episodeLabel}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索资源'),
        actions: <Widget>[
          IconButton(
            tooltip: '下载中心',
            icon: const Icon(Icons.download_for_offline_rounded),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const DownloadCenterPage(),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          onTap: _selectTab,
          tabs: const <Widget>[
            Tab(text: 'B站视频', icon: Icon(Icons.video_library_outlined)),
            Tab(text: '网站资源', icon: Icon(Icons.travel_explore)),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                heading,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: <Widget>[
                  TickerMode(
                    enabled: _index == 0,
                    child: BilibiliVideoPage(
                      embedded: true,
                      initialKeyword: widget.animeName,
                      subjectTitle: widget.animeName,
                      bangumiSubjectId: widget.bangumiSubjectId,
                      aliases: widget.aliases,
                      episodeQuery: query,
                      service: widget.bilibiliService,
                      auth: widget.bilibiliAuth,
                      mappings: widget.bilibiliMappings,
                    ),
                  ),
                  TickerMode(
                    enabled: _index == 1,
                    child: _websitesVisited
                        ? MagnetConfigPage(
                            embedded: true,
                            animeName: widget.animeName,
                            aliases: widget.aliases,
                            bangumiSubjectId: widget.bangumiSubjectId,
                            initialEpisodeNumber: query?.episodeNumber ?? 0,
                            initialEpisodeTitle: query?.episodeTitle ?? '',
                            feedService: widget.feedService,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

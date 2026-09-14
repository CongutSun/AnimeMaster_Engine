import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/dandanplay_service.dart';
import 'detail_page.dart';
import 'magnet_config_page.dart';

class DandanplayDiscoveryPage extends StatefulWidget {
  const DandanplayDiscoveryPage({super.key, this.service});
  final DandanplayService? service;
  @override
  State<DandanplayDiscoveryPage> createState() =>
      _DandanplayDiscoveryPageState();
}

class _DandanplayDiscoveryPageState extends State<DandanplayDiscoveryPage> {
  late final DandanplayService _service = widget.service ?? DandanplayService();
  String _category = 'hot';
  String _period = 'week';
  int _generation = 0;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _items = [];
      _summary = {};
    });
    try {
      final data = await _service.discovery(
        category: _category,
        period: _period,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = (data['bangumiList'] as List? ?? [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .where((m) => m['isRestricted'] != true)
            .toList();
        _summary = data['summary'] is Map
            ? Map<String, dynamic>.from(data['summary'] as Map)
            : {};
        _loading = false;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('热播与新番')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final entry in const {
                    'hot': '热播榜',
                    'rising': '飙升榜',
                    'new': '新番热播',
                    'season': '新番列表',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _category == entry.key,
                      onSelected: (selected) {
                        if (selected && _category != entry.key) {
                          _category = entry.key;
                          _load();
                        }
                      },
                    ),
                ],
              ),
            ),
            if (_category == 'hot' || _category == 'rising')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<String>(
                  initialValue: _period,
                  decoration: const InputDecoration(
                    labelText: '统计周期',
                    border: InputBorder.none,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'week', child: Text('最近一周')),
                    DropdownMenuItem(value: 'month', child: Text('最近一月')),
                    DropdownMenuItem(value: 'quarter', child: Text('最近一季')),
                  ],
                  onChanged: (value) {
                    if (value != null && value != _period) {
                      _period = value;
                      _load();
                    }
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '数据来源：弹弹play开放弹幕网络\n${_summary['dateFrom'] ?? ''}${_summary['dateTo'] == null ? '' : ' 至 ${_summary['dateTo']}'}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _load,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _items.isEmpty
                  ? const Center(child: Text('当前没有可显示的榜单。'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final image = Uri.tryParse(
                            item['imageUrl']?.toString() ?? '',
                          );
                          final id = item['animeId']?.toString() ?? '';
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              leading: SizedBox(
                                width: 46,
                                height: 68,
                                child: image?.scheme == 'https'
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: CachedNetworkImage(
                                          imageUrl: image.toString(),
                                          fit: BoxFit.cover,
                                          errorWidget: (_, _, _) =>
                                              const Icon(Icons.movie_outlined),
                                        ),
                                      )
                                    : const Icon(Icons.movie_outlined),
                              ),
                              title: Text(
                                '${_category == 'season' ? '' : '${item['rank'] ?? index + 1}. '}${item['animeTitle'] ?? '未命名作品'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                [
                                  if (item['heat'] != null)
                                    '热度 ${item['heat']}',
                                  if (item['heatGrowthRate']
                                          ?.toString()
                                          .isNotEmpty ==
                                      true)
                                    '增长 ${item['heatGrowthRate']}',
                                  if (item['isOnAir'] == true) '连载中',
                                ].join(' · '),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: RegExp(r'^\d+$').hasMatch(id)
                                  ? () => Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => DandanplayDetailPage(
                                          animeId: id,
                                          title:
                                              item['animeTitle']?.toString() ??
                                              '',
                                          service: _service,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

class DandanplayDetailPage extends StatefulWidget {
  const DandanplayDetailPage({
    super.key,
    required this.animeId,
    required this.title,
    required this.service,
  });
  final String animeId;
  final String title;
  final DandanplayService service;
  @override
  State<DandanplayDetailPage> createState() => _DandanplayDetailPageState();
}

class _DandanplayDetailPageState extends State<DandanplayDetailPage> {
  late Future<Map<String, dynamic>> _data = widget.service.details(
    widget.animeId,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(snapshot.error.toString()),
                  FilledButton(
                    onPressed: () => setState(() {
                      _data = widget.service.details(widget.animeId);
                    }),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }
        final item = snapshot.data?['bangumi'];
        if (item is! Map) return const Center(child: Text('未找到作品详情。'));
        final uri = Uri.tryParse(item['bangumiUrl']?.toString() ?? '');
        final subjectId =
            uri != null &&
                ['bgm.tv', 'bangumi.tv', 'chii.in'].contains(uri.host)
            ? int.tryParse(
                    RegExp(
                          r'^/subject/(\d+)/?$',
                        ).firstMatch(uri.path)?.group(1) ??
                        '',
                  ) ??
                  0
            : 0;
        final episodes = (item['episodes'] as List? ?? [])
            .whereType<Map>()
            .toList();
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: episodes.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['animeTitle']?.toString() ?? widget.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text('数据来源：弹弹play开放弹幕网络'),
                      const SizedBox(height: 16),
                      SelectableText(
                        item['summary']?.toString() ??
                            item['intro']?.toString() ??
                            '暂无简介',
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          if (subjectId > 0)
                            FilledButton.icon(
                              icon: const Icon(Icons.video_library_outlined),
                              label: const Text('作品详情与追番'),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => DetailPage(
                                    animeId: subjectId,
                                    initialName: widget.title,
                                  ),
                                ),
                              ),
                            ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.search),
                            label: const Text('搜索下载资源'),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => MagnetConfigPage(
                                  animeName: widget.title,
                                  aliases: const [],
                                  bangumiSubjectId: subjectId,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '剧集 · ${episodes.length}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                }
                final episode = episodes[index - 1];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(episode['episodeTitle']?.toString() ?? ''),
                  subtitle: Text(
                    '第 ${episode['episodeNumber'] ?? index} 集 · 搜索下载资源',
                  ),
                  trailing: const Icon(Icons.search),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => MagnetConfigPage(
                        animeName: widget.title,
                        aliases: const [],
                        bangumiSubjectId: subjectId,
                        initialEpisodeNumber:
                            int.tryParse(
                              episode['episodeNumber']?.toString() ?? '',
                            ) ??
                            0,
                        initialEpisodeTitle:
                            episode['episodeTitle']?.toString() ?? '',
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    ),
  );
}

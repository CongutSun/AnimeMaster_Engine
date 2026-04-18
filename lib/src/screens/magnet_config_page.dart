import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/magnet_api.dart';
import '../providers/settings_provider.dart';
import '../utils/magnet_action_helper.dart';
import '../utils/task_title_parser.dart';
import 'download_center_page.dart';

class MagnetConfigPage extends StatefulWidget {
  final String animeName;
  final List<String> aliases;
  final int bangumiSubjectId;

  const MagnetConfigPage({
    super.key,
    required this.animeName,
    required this.aliases,
    this.bangumiSubjectId = 0,
  });

  @override
  State<MagnetConfigPage> createState() => _MagnetConfigPageState();
}

class _MagnetConfigPageState extends State<MagnetConfigPage> {
  final TextEditingController keywordController = TextEditingController();
  final TextEditingController includeController = TextEditingController();
  final TextEditingController qualityController = TextEditingController();
  final TextEditingController excludeController = TextEditingController();

  List<Map<String, String>> selectedSources = <Map<String, String>>[];
  List<Map<String, String>> searchResults = <Map<String, String>>[];
  bool isSearching = false;
  bool hasSearched = false;

  @override
  void initState() {
    super.initState();
    keywordController.text = widget.animeName;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSources());
  }

  @override
  void dispose() {
    keywordController.dispose();
    includeController.dispose();
    qualityController.dispose();
    excludeController.dispose();
    super.dispose();
  }

  void _loadSources() {
    final SettingsProvider provider = Provider.of<SettingsProvider>(
      context,
      listen: false,
    );
    setState(() {
      selectedSources = List<Map<String, String>>.from(provider.rssSources);
    });
  }

  Future<void> _startSearch() async {
    if (keywordController.text.trim().isEmpty) {
      return;
    }
    if (selectedSources.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一个检索源。')));
      return;
    }

    setState(() {
      isSearching = true;
      hasSearched = true;
      searchResults = <Map<String, String>>[];
    });

    final List<Map<String, String>> results = await MagnetApi.searchTorrents(
      keyword: keywordController.text.trim(),
      selectedSources: selectedSources,
      mustInclude: includeController.text.trim(),
      quality: qualityController.text.trim(),
      exclude: excludeController.text.trim(),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      searchResults = results;
      isSearching = false;
    });
  }

  void _showAliasesDialog() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.aliases.length,
          itemBuilder: (BuildContext context, int index) {
            final String name = widget.aliases[index];
            return ListTile(
              leading: const Icon(Icons.label_outline),
              title: Text(name),
              onTap: () {
                setState(() {
                  keywordController.text = name;
                });
                Navigator.pop(context);
              },
            );
          },
        ),
      ),
    );
  }

  void _copyResource(Map<String, String> result) {
    final String content = result['magnet']?.trim().isNotEmpty == true
        ? result['magnet']!
        : (result['torrent']?.trim().isNotEmpty == true
              ? result['torrent']!
              : result['url'] ?? '');
    if (content.isEmpty) {
      return;
    }
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('链接已复制到剪贴板。'),
        backgroundColor: Colors.green,
      ),
    );
  }

  String _preferredDownloadUrl(Map<String, String> result) {
    if (result['torrent']?.trim().isNotEmpty == true) {
      return result['torrent']!.trim();
    }
    if (result['magnet']?.trim().isNotEmpty == true) {
      return result['magnet']!.trim();
    }
    return result['url']?.trim() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> allSources = context
        .watch<SettingsProvider>()
        .rssSources;

    return Scaffold(
      appBar: AppBar(
        title: const Text('聚合搜刮'),
        actions: <Widget>[
          IconButton(
            tooltip: '缓存中心',
            icon: const Icon(Icons.download_for_offline_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const DownloadCenterPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '检索条件',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: keywordController,
                          decoration: const InputDecoration(
                            labelText: '检索词',
                            hintText: '建议优先使用罗马音或英文名',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _showAliasesDialog,
                        icon: const Icon(Icons.list_alt),
                        label: const Text('别名'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: includeController,
                    decoration: const InputDecoration(
                      labelText: '必须包含',
                      hintText: '例如：简中、WebRip、合集',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: qualityController,
                          decoration: const InputDecoration(
                            labelText: '画质过滤',
                            hintText: '例如：1080',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: excludeController,
                          decoration: const InputDecoration(
                            labelText: '排除词',
                            hintText: '例如：繁体',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '检索源',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: allSources.map((Map<String, String> source) {
                      final bool isSelected = selectedSources.any(
                        (Map<String, String> item) =>
                            item['name'] == source['name'],
                      );
                      return FilterChip(
                        label: Text(source['name'] ?? '未知源'),
                        selected: isSelected,
                        onSelected: (bool selected) {
                          setState(() {
                            if (selected) {
                              selectedSources.add(source);
                            } else {
                              selectedSources.removeWhere(
                                (Map<String, String> item) =>
                                    item['name'] == source['name'],
                              );
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isSearching ? null : _startSearch,
                      icon: isSearching
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.travel_explore),
                      label: Text(isSearching ? '正在并发检索...' : '开始搜刮'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '说明：如果结果同时提供 magnet 和 .torrent，下载与播放将优先使用 .torrent 直链，以缩短元数据解析时间。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (hasSearched) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              isSearching ? '正在获取结果...' : '检索结果：${searchResults.length} 条',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (!isSearching && searchResults.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '没有找到符合条件的资源。建议缩短检索词，或取消部分过滤条件。',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ...searchResults.map((Map<String, String> result) {
              final String title = result['title'] ?? '未知资源';
              final String episodeLabel = TaskTitleParser.extractEpisodeLabel(
                title,
              );
              final String targetDownloadUrl = _preferredDownloadUrl(result);
              final bool hasTorrent =
                  result['torrent']?.trim().isNotEmpty == true;

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          _MetaChip(label: result['source'] ?? '未知源'),
                          if (result['date']?.isNotEmpty == true)
                            _MetaChip(label: result['date']!),
                          _MetaChip(label: hasTorrent ? '.torrent 直链' : '磁力'),
                          if (episodeLabel.isNotEmpty)
                            _MetaChip(label: episodeLabel),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed: () => _copyResource(result),
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('复制'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: targetDownloadUrl.isEmpty
                                ? null
                                : () {
                                    MagnetActionHelper.process(
                                      context,
                                      targetDownloadUrl,
                                      autoPlay: true,
                                      preferredTitle: title,
                                      subjectTitle: widget.animeName,
                                      episodeLabel: episodeLabel,
                                      bangumiSubjectId: widget.bangumiSubjectId,
                                    );
                                  },
                            icon: const Icon(Icons.play_circle_fill_rounded),
                            label: const Text('添加并播放'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;

  const _MetaChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

import 'dart:async';

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
  final int initialEpisodeNumber;
  final String initialEpisodeTitle;

  const MagnetConfigPage({
    super.key,
    required this.animeName,
    required this.aliases,
    this.bangumiSubjectId = 0,
    this.initialEpisodeNumber = 0,
    this.initialEpisodeTitle = '',
  });

  @override
  State<MagnetConfigPage> createState() => _MagnetConfigPageState();
}

class _MagnetConfigPageState extends State<MagnetConfigPage> {
  final TextEditingController keywordController = TextEditingController();
  final TextEditingController includeController = TextEditingController();
  final TextEditingController qualityController = TextEditingController();
  final TextEditingController excludeController = TextEditingController();
  final TextEditingController episodeController = TextEditingController();

  List<Map<String, String>> selectedSources = <Map<String, String>>[];
  List<Map<String, String>> searchResults = <Map<String, String>>[];
  bool isSearching = false;
  bool hasSearched = false;
  int? searchedEpisodeNumber;
  int _searchGeneration = 0;
  int _completedSources = 0;
  final List<String> _failedSources = [];
  final Map<String, String> _resourceErrors = {};
  bool _processing = false;
  String _sortOrder = '推荐';

  @override
  void initState() {
    super.initState();
    keywordController.text = widget.animeName;
    if (widget.initialEpisodeNumber > 0) {
      episodeController.text = widget.initialEpisodeNumber.toString();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSources());
  }

  @override
  void dispose() {
    keywordController.dispose();
    includeController.dispose();
    qualityController.dispose();
    excludeController.dispose();
    episodeController.dispose();
    super.dispose();
  }

  void _loadSources() {
    final SettingsProvider provider = Provider.of<SettingsProvider>(
      context,
      listen: false,
    );
    setState(() {
      selectedSources = provider.rssSources
          .where((s) => s['enabled'] != 'false')
          .toList();
    });
  }

  Future<void> _startSearch() async {
    if (_processing) return;
    if (keywordController.text.trim().isEmpty) {
      return;
    }
    if (selectedSources.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一个资源源。')));
      return;
    }
    final String rawEpisode = episodeController.text.trim();
    final int? targetEpisodeNumber = rawEpisode.isEmpty
        ? null
        : int.tryParse(rawEpisode);
    if (rawEpisode.isNotEmpty &&
        (targetEpisodeNumber == null || targetEpisodeNumber <= 0)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入正确的集数。')));
      return;
    }

    setState(() {
      isSearching = true;
      hasSearched = true;
      searchResults = <Map<String, String>>[];
      searchedEpisodeNumber = targetEpisodeNumber;
      _completedSources = 0;
      _failedSources.clear();
      _resourceErrors.clear();
    });
    FocusScope.of(context).unfocus();
    final generation = ++_searchGeneration;

    final List<Map<String, String>> results = await MagnetApi.searchTorrents(
      keyword: keywordController.text.trim(),
      aliases: keywordController.text.trim() == widget.animeName.trim()
          ? widget.aliases
          : const [],
      selectedSources: List.of(selectedSources),
      mustInclude: includeController.text.trim(),
      quality: qualityController.text.trim(),
      exclude: excludeController.text.trim(),
      targetEpisodeNumber: targetEpisodeNumber,
      onResults: (items) {
        if (mounted && generation == _searchGeneration) {
          setState(() => searchResults = items);
        }
      },
      onSourceComplete: (name, success) {
        if (mounted && generation == _searchGeneration) {
          setState(() {
            _completedSources++;
            if (!success) _failedSources.add(name);
          });
        }
      },
    );

    if (!mounted || generation != _searchGeneration) {
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

  Future<void> _processResource(
    Map<String, String> result,
    String episodeLabel,
    bool autoPlay,
  ) async {
    if (_processing) return;
    final url = _preferredDownloadUrl(result);
    setState(() {
      _processing = true;
      _resourceErrors.remove(url);
    });
    try {
      final error = await MagnetActionHelper.process(
        context,
        url,
        autoPlay: autoPlay,
        preferredTitle: result['title'] ?? '',
        fallbackSource: result['magnet'] ?? '',
        subjectTitle: widget.animeName,
        episodeLabel: episodeLabel,
        bangumiSubjectId: widget.bangumiSubjectId,
      );
      if (mounted && error != null) {
        setState(() => _resourceErrors[url] = error);
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> allSources = context
        .watch<SettingsProvider>()
        .rssSources
        .where((s) => s['enabled'] != 'false')
        .toList();
    final sortedResults = List<Map<String, String>>.of(searchResults)
      ..sort((a, b) {
        if (_sortOrder == '推荐') {
          final direct =
              (b['torrent']?.isNotEmpty == true ? 1 : 0) -
              (a['torrent']?.isNotEmpty == true ? 1 : 0);
          if (direct != 0) return direct;
        }
        if (_sortOrder == '来源') {
          return (a['source'] ?? '').compareTo(b['source'] ?? '');
        }
        return (DateTime.tryParse(b['date'] ?? '') ?? DateTime(1970)).compareTo(
          DateTime.tryParse(a['date'] ?? '') ?? DateTime(1970),
        );
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('番剧资源搜索'),
        actions: <Widget>[
          IconButton(
            tooltip: '下载中心',
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
                    '搜索条件',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: keywordController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _startSearch(),
                          decoration: const InputDecoration(
                            labelText: '番剧名称',
                            hintText: '输入番剧名称，也可以选择别名',
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
                    controller: episodeController,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      labelText: '指定集数（可选）',
                      hintText: '例如：12',
                      helperText: widget.initialEpisodeTitle.trim().isEmpty
                          ? '填写后只显示该单集，不需要手动拼 EP12'
                          : '当前：${widget.initialEpisodeTitle.trim()}',
                      suffixIcon: episodeController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '搜索全部资源',
                              onPressed: () {
                                setState(episodeController.clear);
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => unawaited(_startSearch()),
                  ),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('筛选与来源'),
                    subtitle: Text('已选择 ${selectedSources.length} 个来源'),
                    children: [
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
                        '搜索来源',
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
                            onSelected: isSearching
                                ? null
                                : (bool selected) {
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
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isSearching || _processing
                          ? null
                          : _startSearch,
                      icon: isSearching
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.travel_explore),
                      label: Text(isSearching ? '正在搜索...' : '搜索资源'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '支持下载后观看或边下边播。资源链接可用性以实际解析结果为准。',
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
              isSearching
                  ? '已完成 $_completedSources 个来源 · ${searchResults.length} 条结果'
                  : searchedEpisodeNumber == null
                  ? '搜索结果：${searchResults.length} 条'
                  : '第 $searchedEpisodeNumber 集：${searchResults.length} 条',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (_failedSources.isNotEmpty)
              Text(
                '以下来源暂不可用：${_failedSources.join('、')}。可重新搜索。',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Row(
              children: [
                const Text('排序：'),
                DropdownButton<String>(
                  value: _sortOrder,
                  items: ['推荐', '最新', '来源']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _sortOrder = value!),
                ),
                if (isSearching)
                  TextButton(
                    onPressed: () => setState(() {
                      ++_searchGeneration;
                      isSearching = false;
                    }),
                    child: const Text('停止等待'),
                  ),
              ],
            ),
            if (!isSearching && searchResults.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _failedSources.length == selectedSources.length
                        ? '搜索来源暂不可用，请稍后重试。'
                        : '没有找到符合条件的资源。试试别名或减少筛选条件。',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ...sortedResults.map((Map<String, String> result) {
              final String title = TaskTitleParser.stripSourcePrefix(
                result['title'] ?? '未知资源',
              );
              final String parsedEpisodeLabel =
                  TaskTitleParser.extractEpisodeLabel(title);
              final String episodeLabel = parsedEpisodeLabel.isNotEmpty
                  ? parsedEpisodeLabel
                  : searchedEpisodeNumber == null
                  ? ''
                  : TaskTitleParser.buildEpisodeDisplayLabel(
                      episodeNumber: searchedEpisodeNumber!,
                      episodeTitle: widget.initialEpisodeTitle,
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
                          _MetaChip(label: hasTorrent ? '种子链接 · 未验证' : '磁力链接'),
                          if (episodeLabel.isNotEmpty)
                            _MetaChip(label: episodeLabel),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_resourceErrors[targetDownloadUrl] != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            '${_resourceErrors[targetDownloadUrl]}\n可再次点击下载重试，或复制链接到其他下载器。',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed: () => _copyResource(result),
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('复制'),
                          ),
                          OutlinedButton.icon(
                            onPressed: targetDownloadUrl.isEmpty || _processing
                                ? null
                                : () => _processResource(
                                    result,
                                    episodeLabel,
                                    true,
                                  ),
                            icon: const Icon(Icons.play_circle_fill_rounded),
                            label: const Text('播放'),
                          ),
                          FilledButton.icon(
                            onPressed: targetDownloadUrl.isEmpty || _processing
                                ? null
                                : () => _processResource(
                                    result,
                                    episodeLabel,
                                    false,
                                  ),
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: const Text('下载'),
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

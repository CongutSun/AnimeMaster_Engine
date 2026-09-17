import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/bangumi_api.dart';
import '../models/anime.dart';
import '../models/rss_resource.dart';
import '../providers/settings_provider.dart';
import '../services/rss_feed_service.dart';
import '../services/rss_inbox_store.dart';
import '../utils/magnet_action_helper.dart';
import '../utils/haptic_helper.dart';
import 'settings_page.dart';

class RssInboxPage extends StatefulWidget {
  const RssInboxPage({super.key, this.store});
  final RssInboxStore? store;
  @override
  State<RssInboxPage> createState() => _RssInboxPageState();
}

class _RssInboxPageState extends State<RssInboxPage> {
  late final store = widget.store ?? RssInboxStore.instance;
  List<Anime> _watching = [];
  String _filter = 'all', _query = '';
  String? _watchError;
  bool _loading = true, _downloading = false;
  bool _refreshActive = false;
  String _loadedAccount = '';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    if (!mounted || _refreshActive) return;
    _refreshActive = true;
    final settings = context.read<SettingsProvider>();
    final account = settings.bgmAcc;
    setState(() {
      _loading = true;
      _watchError = null;
      if (_loadedAccount != account) _watching = [];
      _loadedAccount = account;
    });
    try {
      await store.refresh(settings.rssSources, force: force);
      if (account.isNotEmpty) {
        await settings.ensureBangumiAccessToken();
        final items = await BangumiApi.instance.getUserCollectionList(
          account,
          token: settings.bgmToken,
        );
        if (mounted && settings.bgmAcc == account) {
          _watching = items
              .map((e) => Anime.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        }
      } else {
        _watching = [];
      }
    } catch (_) {
      _watchError = '在看列表暂时无法读取，仍可浏览订阅资源。';
    } finally {
      _refreshActive = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, String> _rule(Anime anime) =>
      store.rules['${context.read<SettingsProvider>().bgmAcc}:${anime.id}'] ??
      {};
  List<Anime> _matches(RssInboxEntry entry) {
    if (_loadedAccount != context.read<SettingsProvider>().bgmAcc) return [];
    if (entry.subjectId != null) {
      return _watching.where((a) => a.id == entry.subjectId).toList();
    }
    return _watching.where((anime) {
      final rule = _rule(anime);
      if (rule['enabled'] == 'false') return false;
      final title = entry.resource.title.toLowerCase();
      final source = rule['source'] ?? '';
      if (source.isNotEmpty && source != entry.sourceId) return false;
      for (final field in ['include', 'quality']) {
        final term = rule[field]?.trim().toLowerCase() ?? '';
        if (term.isNotEmpty && !title.contains(term)) return false;
      }
      final exclude = rule['exclude']?.trim().toLowerCase() ?? '';
      if (exclude.isNotEmpty && title.contains(exclude)) return false;
      return RssFeedService.matchesTitle(title, [
        anime.name,
        anime.nameCn,
        ...?(rule['aliases']?.split('\n')),
      ]);
    }).toList();
  }

  int? _episode(RssInboxEntry entry, List<Anime> matches) {
    final number = RssInboxStore.episode(entry.resource.title);
    if (number == null) return null;
    return number +
        (matches.length == 1
            ? int.tryParse(_rule(matches.single)['offset'] ?? '') ?? 0
            : 0);
  }

  String _category(RssInboxEntry entry) {
    if (entry.state != 'new') return 'done';
    final matches = _matches(entry), episode = _episode(entry, _matches(entry));
    if (matches.isEmpty) return 'unmatched';
    if (matches.length > 1 ||
        episode == null ||
        episode <= 0 ||
        (matches.single.eps > 0 && episode > matches.single.eps)) {
      return 'review';
    }
    if (episode <= matches.single.epStatus) return 'done';
    return 'new';
  }

  Future<void> _save(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('记录保存失败，请稍后重试。')));
      }
    }
  }

  Future<void> _choose({RssInboxEntry? entry}) async {
    if (_watching.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先登录 Bangumi 并将番剧加入“在看”。')));
      return;
    }
    final selected = await showModalBottomSheet<Anime>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                entry == null ? '选择要设置规则的番剧' : '关联到哪部番剧？',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _watching.length,
                itemBuilder: (_, index) => ListTile(
                  title: Text(_watching[index].displayName),
                  subtitle: Text('已看 ${_watching[index].epStatus} 集'),
                  onTap: () => Navigator.pop(ctx, _watching[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (entry != null) {
      await _save(() => store.mark(entry, entry.state, subjectId: selected.id));
      return;
    }
    final settings = context.read<SettingsProvider>();
    final account = settings.bgmAcc;
    final rule = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _RssRuleDialog(
        anime: selected,
        rule: _rule(selected),
        sources: settings.rssSources.where(isSubscriptionSource).toList(),
      ),
    );
    if (rule != null && mounted) {
      await _save(() => store.saveRule(account, selected.id, rule));
    }
  }

  Future<void> _download(RssInboxEntry entry) async {
    if (_downloading) return;
    final matches = _matches(entry);
    final anime = matches.length == 1 ? matches.single : null;
    final episode = _episode(entry, matches);
    final confirmed = await showDialog<int>(
      context: context,
      builder: (_) =>
          _RssDownloadDialog(entry: entry, anime: anime, episode: episode),
    );
    if (!mounted || confirmed == null) return;
    setState(() => _downloading = true);
    try {
      var added = false;
      final error = await MagnetActionHelper.process(
        context,
        entry.resource.downloadUrl,
        onTaskAdded: () => added = true,
        autoPlay: false,
        preferredTitle: entry.resource.title,
        subjectTitle: anime?.displayName ?? '',
        bangumiSubjectId: confirmed > 0 ? anime?.id ?? 0 : 0,
        episodeLabel: confirmed > 0 ? '第 $confirmed 集' : '',
        fallbackSource: entry.resource.magnet,
      );
      if (added) {
        await _save(() => store.mark(entry, 'downloaded'));
      } else if (error != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未能加入下载，请检查资源是否可用后重试。')));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _settings() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('订阅更新'),
      actions: [
        IconButton(
          tooltip: '追番规则',
          onPressed: _loading ? null : () => _choose(),
          icon: const Icon(Icons.tune),
        ),
        IconButton(
          tooltip: '管理来源',
          onPressed: _settings,
          icon: const Icon(Icons.rss_feed),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final sources = context
            .watch<SettingsProvider>()
            .rssSources
            .where((s) => isSubscriptionSource(s) && s['enabled'] != 'false')
            .toList();
        final ids = sources.map(rssSourceId).toSet();
        final visible =
            store.entries
                .where(
                  (entry) =>
                      ids.contains(entry.sourceId) &&
                      (_filter == 'all' || _category(entry) == _filter) &&
                      (_query.isEmpty ||
                          entry.resource.title.toLowerCase().contains(
                            _query.toLowerCase(),
                          )),
                )
                .toList()
              ..sort(
                (a, b) => (b.resource.publishedAt ?? b.discoveredAt).compareTo(
                  a.resource.publishedAt ?? a.discoveredAt,
                ),
              );
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value.trim()),
                    decoration: const InputDecoration(
                      hintText: '搜索订阅中的番名或字幕组',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final item in const {
                          'all': '全部',
                          'new': '追番更新',
                          'review': '待确认',
                          'unmatched': '未匹配',
                          'done': '已处理',
                        }.entries)
                          ChoiceChip(
                            label: Text(item.value),
                            selected: _filter == item.key,
                            onSelected: (_) {
                              quickHaptic();
                              setState(() => _filter = item.key);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${visible.length} 条资源 · ${sources.length} 个订阅源',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _loading || store.refreshing
                            ? null
                            : () => _refresh(force: true),
                        icon: const Icon(Icons.refresh),
                        label: const Text('刷新'),
                      ),
                    ],
                  ),
                ),
                if (_loading || store.refreshing)
                  const LinearProgressIndicator(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _refresh(force: true),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: visible.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (store.storageError != null ||
                                  _watchError != null)
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      store.storageError ?? _watchError!,
                                    ),
                                  ),
                                ),
                              for (final source in sources)
                                if (store.errors[rssSourceId(source)]
                                    case final String error)
                                  Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Text('${source['name']}：$error'),
                                    ),
                                  ),
                              if (visible.isEmpty && !_loading)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 32,
                                  ),
                                  child: Column(
                                    children: [
                                      const Icon(Icons.rss_feed, size: 40),
                                      const SizedBox(height: 12),
                                      Text(
                                        sources.isEmpty
                                            ? '添加订阅，集中查看新资源'
                                            : '暂无符合条件的资源',
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        '刷新订阅不会自动下载，也不会更改观看进度。',
                                        textAlign: TextAlign.center,
                                      ),
                                      if (sources.isEmpty)
                                        TextButton(
                                          onPressed: _settings,
                                          child: const Text('添加 RSS 来源'),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        }
                        final entry = visible[index - 1],
                            matches = _matches(visible[index - 1]);
                        final episode = _episode(entry, matches);
                        final category = _category(entry);
                        final subtitle = matches.isEmpty
                            ? '尚未关联作品'
                            : matches.map((a) => a.displayName).join(' / ');
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.resource.title,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '$subtitle${episode == null ? '' : ' · 第 $episode 集'}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${entry.sourceName} · ${entry.state == 'downloaded'
                                      ? '已加入下载'
                                      : entry.state == 'ignored'
                                      ? '已忽略'
                                      : category == 'done'
                                      ? '已看集数'
                                      : category == 'review'
                                      ? '请确认作品与集数'
                                      : category == 'new'
                                      ? '发现未看集数'
                                      : '订阅资源'}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (entry.resource.publishedAt != null)
                                  Text(
                                    entry.resource.publishedAt!
                                        .toLocal()
                                        .toString()
                                        .split('.')
                                        .first,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    FilledButton.icon(
                                      onPressed:
                                          _downloading ||
                                              entry
                                                  .resource
                                                  .downloadUrl
                                                  .isEmpty ||
                                              entry.state == 'downloaded'
                                          ? null
                                          : () => _download(entry),
                                      icon: const Icon(Icons.download_outlined),
                                      label: Text(
                                        entry.resource.downloadUrl.isEmpty
                                            ? '未发现下载链接'
                                            : '下载',
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => _choose(entry: entry),
                                      child: const Text('关联作品'),
                                    ),
                                    TextButton(
                                      onPressed: () => _save(
                                        () => store.mark(
                                          entry,
                                          entry.state == 'new'
                                              ? 'ignored'
                                              : 'new',
                                        ),
                                      ),
                                      child: Text(
                                        entry.state == 'new' ? '忽略' : '恢复',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _RssDownloadDialog extends StatefulWidget {
  const _RssDownloadDialog({required this.entry, this.anime, this.episode});
  final RssInboxEntry entry;
  final Anime? anime;
  final int? episode;
  @override
  State<_RssDownloadDialog> createState() => _RssDownloadDialogState();
}

class _RssDownloadDialogState extends State<_RssDownloadDialog> {
  late final field = TextEditingController(
    text:
        widget.episode != null &&
            widget.episode! > 0 &&
            (widget.anime == null ||
                widget.anime!.eps <= 0 ||
                widget.episode! <= widget.anime!.eps)
        ? '${widget.episode}'
        : '',
  );
  String? error;
  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('加入下载？'),
    scrollable: true,
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.entry.resource.title),
          const SizedBox(height: 16),
          Text(
            widget.anime == null
                ? '作品尚未关联，将按资源标题保存。'
                : '关联：${widget.anime!.displayName}',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: field,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '确认集数（可留空）',
              errorText: error,
              helperText: '不确定或为合集时留空，不绑定观看进度。',
              helperMaxLines: 2,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          final text = field.text.trim();
          final value = text.isEmpty ? 0 : int.tryParse(text);
          if (value == null ||
              (text.isNotEmpty && value <= 0) ||
              (widget.anime != null &&
                  widget.anime!.eps > 0 &&
                  value > widget.anime!.eps)) {
            setState(() => error = '请输入有效集数，不确定时请留空。');
            return;
          }
          Navigator.pop(context, value);
        },
        child: const Text('下载'),
      ),
    ],
  );
}

class _RssRuleDialog extends StatefulWidget {
  const _RssRuleDialog({
    required this.anime,
    required this.rule,
    required this.sources,
  });
  final Anime anime;
  final Map<String, String> rule;
  final List<Map<String, String>> sources;
  @override
  State<_RssRuleDialog> createState() => _RssRuleDialogState();
}

class _RssRuleDialogState extends State<_RssRuleDialog> {
  late final fields = {
    for (final key in ['aliases', 'include', 'quality', 'exclude', 'offset'])
      key: TextEditingController(text: widget.rule[key] ?? ''),
  };
  late bool enabled = widget.rule['enabled'] != 'false';
  late String source =
      widget.sources.any((s) => rssSourceId(s) == widget.rule['source'])
      ? widget.rule['source']!
      : '';
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.anime.displayName} · 资源订阅'),
    scrollable: true,
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('匹配追番更新'),
            value: enabled,
            onChanged: (v) => setState(() => enabled = v),
          ),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: source,
            decoration: const InputDecoration(labelText: '来源'),
            items: [
              const DropdownMenuItem(value: '', child: Text('所有订阅源')),
              for (final item in widget.sources)
                DropdownMenuItem(
                  value: rssSourceId(item),
                  child: Text(
                    item['name'] ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => source = v!,
          ),
          for (final field in const {
            'aliases': '其他番名（每行一个）',
            'include': '字幕组或必须包含的词',
            'quality': '画质（例如 1080p）',
            'exclude': '排除词',
            'offset': '集数偏移（默认 0）',
          }.entries)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextField(
                controller: fields[field.key],
                maxLines: field.key == 'aliases' ? 3 : 1,
                decoration: InputDecoration(labelText: field.value),
              ),
            ),
          const SizedBox(height: 12),
          const Text('仅发现资源，由你确认下载。合集、特别篇和不明确的集数会进入待确认。'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          final offset = fields['offset']!.text.trim();
          if (offset.isNotEmpty && int.tryParse(offset) == null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('集数偏移请输入整数。')));
            return;
          }
          Navigator.pop(context, {
            'enabled': enabled.toString(),
            'source': source,
            for (final field in fields.entries)
              field.key: field.value.text.trim(),
          });
        },
        child: const Text('保存'),
      ),
    ],
  );
}

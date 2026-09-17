import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/rss_resource.dart';
import '../providers/settings_provider.dart';
import '../services/rss_feed_service.dart';
import 'rss_inbox_entry_point.dart';

class RssSourcesCard extends StatefulWidget {
  const RssSourcesCard({super.key});
  @override
  State<RssSourcesCard> createState() => _RssSourcesCardState();
}

class _RssSourcesCardState extends State<RssSourcesCard> {
  bool _saving = false;
  Future<void> _edit([int? index]) async {
    final settings = context.read<SettingsProvider>();
    final source = index == null ? null : settings.rssSources[index];
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => RssSourceDialog(source: source),
    );
    if (result == null || !mounted) return;
    await _save(
      () => index == null
          ? settings.addRssSource(
              result['name']!,
              result['url']!,
              type: result['type'],
            )
          : settings.updateRssSource(index, {...?source, ...result}),
    );
  }

  Future<void> _save(Future<void> Function() operation) async {
    setState(() => _saving = true);
    try {
      await operation();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请检查是否重复添加，或稍后重试。')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(int index) async {
    final settings = context.read<SettingsProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这个来源？'),
        content: const Text('已有下载会保留，订阅更新将停止。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _save(() => settings.removeRssSource(index));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final sources = settings.rssSources;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'RSS 资源源',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: _saving ? null : () => _edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('添加'),
                ),
              ],
            ),
            Text(
              '搜索源用于按番名找资源；订阅源用于接收更新。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            const RssInboxEntryPoint(),
            if (sources.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('添加网站提供的 RSS 地址即可开始。'),
              ),
            for (var i = 0; i < sources.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  isSubscriptionSource(sources[i])
                      ? Icons.rss_feed
                      : Icons.search,
                ),
                title: Text(sources[i]['name'] ?? '未命名来源'),
                subtitle: Text(
                  '${isSubscriptionSource(sources[i]) ? '订阅源' : '搜索源'} · ${Uri.tryParse(sources[i]['url'] ?? '')?.host ?? ''}\n${sources[i]['enabled'] == 'false' ? '已停用' : '已启用'} · 地址安全保存在本机',
                ),
                isThreeLine: true,
                onTap: _saving ? null : () => _edit(i),
                trailing: PopupMenuButton<String>(
                  enabled: !_saving,
                  tooltip: '来源选项',
                  onSelected: (value) {
                    if (value == 'edit') {
                      _edit(i);
                    } else if (value == 'delete') {
                      _remove(i);
                    } else {
                      _save(
                        () => settings.updateRssSource(i, {
                          ...sources[i],
                          'enabled': sources[i]['enabled'] == 'false'
                              ? 'true'
                              : 'false',
                        }),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('编辑与测试')),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(
                        sources[i]['enabled'] == 'false' ? '启用' : '停用',
                      ),
                    ),
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ),
            if (_saving) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class RssSourceDialog extends StatefulWidget {
  const RssSourceDialog({super.key, this.source, this.service});
  final Map<String, String>? source;
  final RssFeedService? service;
  @override
  State<RssSourceDialog> createState() => _RssSourceDialogState();
}

class _RssSourceDialogState extends State<RssSourceDialog> {
  late final _name = TextEditingController(text: widget.source?['name']);
  late final _url = TextEditingController(text: widget.source?['url']);
  late String _type = widget.source == null
      ? 'auto'
      : (isSubscriptionSource(widget.source!) ? 'subscription' : 'search');
  bool _busy = false, _showUrl = false;
  String? _message;
  bool _success = false;
  String get _kind => _type == 'auto'
      ? (_url.text.contains('{keyword}') ? 'search' : 'subscription')
      : _type;
  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  String? _validate() =>
      validateRssUrl(_url.text.trim(), search: _kind == 'search');
  Future<void> _test() async {
    final error = _validate();
    if (error != null) {
      setState(() {
        _message = error;
        _success = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await (widget.service ?? RssFeedService.instance).fetch(
        _url.text.trim().replaceAll('{keyword}', Uri.encodeComponent('动画')),
        force: true,
      );
      if (!mounted) return;
      final downloadable = result.items
          .where((e) => e.downloadUrl.isNotEmpty)
          .length;
      final dates =
          result.items.map((e) => e.publishedAt).whereType<DateTime>().toList()
            ..sort();
      setState(() {
        _success = true;
        _message =
            '连接成功 · ${result.items.length} 条内容 · $downloadable 条可下载'
            '${dates.isEmpty ? '' : '\n最新发布：${dates.last.toLocal().toString().split('.').first}'}';
        if (_name.text.trim().isEmpty && result.title.isNotEmpty) {
          _name.text = result.title;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _success = false;
          _message = e is RssFeedException ? e.message : '测试失败，请检查订阅地址。';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.source == null ? '添加 RSS 来源' : '编辑 RSS 来源'),
    scrollable: true,
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '例如：我的动画订阅',
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _type,
            decoration: const InputDecoration(labelText: '来源类型'),
            items: const [
              DropdownMenuItem(value: 'auto', child: Text('自动识别')),
              DropdownMenuItem(
                value: 'subscription',
                child: Text('订阅源 · 固定地址'),
              ),
              DropdownMenuItem(
                value: 'search',
                child: Text('搜索源 · 包含 {keyword}'),
              ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _type = value!;
                    _message = null;
                  }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            enabled: !_busy,
            obscureText: !_showUrl,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() => _message = null),
            decoration: InputDecoration(
              labelText: 'RSS 地址',
              hintText: '粘贴网站提供的 HTTPS 地址',
              suffixIcon: IconButton(
                tooltip: _showUrl ? '隐藏地址' : '显示地址',
                onPressed: () => setState(() => _showUrl = !_showUrl),
                icon: Icon(_showUrl ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('个人订阅地址仅保存在本机。固定订阅只能搜索已收录的更新，不能覆盖网站全部历史资源。'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _test,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
            label: Text(_busy ? '正在测试…' : '测试连接'),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _message!,
                style: TextStyle(
                  color: _success
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _busy
            ? null
            : () {
                final error = _name.text.trim().isEmpty
                    ? '请输入来源名称。'
                    : _validate();
                if (error != null) {
                  setState(() {
                    _success = false;
                    _message = error;
                  });
                  return;
                }
                Navigator.pop(context, {
                  'name': _name.text.trim(),
                  'url': _url.text.trim(),
                  'type': _kind,
                });
              },
        child: const Text('保存'),
      ),
    ],
  );
}

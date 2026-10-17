import 'dart:async';

import 'package:flutter/material.dart';

import '../models/bilibili_video.dart';
import '../models/online_episode_source.dart';
import '../repositories/bilibili_episode_mapping_repository.dart';
import '../services/bilibili_auth_service.dart';
import '../services/bilibili_video_service.dart';
import '../widgets/bilibili_account_button.dart';
import 'bilibili_video_details_page.dart';

class BilibiliVideoPage extends StatefulWidget {
  final BilibiliVideoService? service;
  final BilibiliAuthService? auth;
  final BilibiliEpisodeMappingRepository? mappings;
  final String? initialBvid;
  final OnlineEpisodeQuery? episodeQuery;
  final String initialKeyword;
  final String subjectTitle;
  final int bangumiSubjectId;
  final List<String> aliases;
  final bool embedded;

  const BilibiliVideoPage({
    super.key,
    this.service,
    this.auth,
    this.mappings,
    this.initialBvid,
    this.episodeQuery,
    this.initialKeyword = '',
    this.subjectTitle = '',
    this.bangumiSubjectId = 0,
    this.aliases = const <String>[],
    this.embedded = false,
  });

  @override
  State<BilibiliVideoPage> createState() => _BilibiliVideoPageState();
}

class _BilibiliVideoPageState extends State<BilibiliVideoPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _resultsScroll = ScrollController();
  late final BilibiliAuthService _auth;
  late final BilibiliVideoService _service;
  List<BilibiliSearchHit> _hits = <BilibiliSearchHit>[];
  String _searchKeyword = '';
  int _page = 0;
  int _totalPages = 0;
  bool _loading = false;
  bool _openingVideo = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _auth = widget.auth ?? BilibiliAuthService.instance;
    _service = widget.service ?? BilibiliVideoService(auth: _auth);
    _input.text = widget.initialKeyword.isNotEmpty
        ? widget.initialKeyword
        : widget.episodeQuery?.subjectTitle ?? '';
    if (widget.initialBvid == null) unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final String initialKeyword = _input.text;
    try {
      await _auth.initialize();
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取本机授权，请打开登录页重试。');
    }
    if (!mounted) return;
    if (initialKeyword.isNotEmpty &&
        _input.text == initialKeyword &&
        _page == 0) {
      await _openInput();
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _resultsScroll.dispose();
    super.dispose();
  }

  Future<void> _openInput() async {
    if (_loading || _openingVideo) return;
    final String input = _input.text.trim();
    if (input.startsWith('BV') || input.contains('://')) {
      try {
        final String bvid = BilibiliVideoService.parseBvid(input);
        await _openVideo(bvid);
      } catch (error) {
        if (mounted) setState(() => _error = _message(error));
      }
    } else {
      await _search(input);
    }
  }

  String _message(Object error) => error is BilibiliVideoException
      ? error.message
      : error is BilibiliAuthException
      ? error.message
      : '操作失败，请稍后重试。';

  Future<void> _openVideo(String bvid) async {
    if (_loading || _openingVideo) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _openingVideo = true;
      _error = '';
    });
    try {
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute<void>(builder: (_) => _details(bvid)));
    } finally {
      if (mounted) setState(() => _openingVideo = false);
    }
  }

  BilibiliVideoDetailsPage _details(String bvid) => BilibiliVideoDetailsPage(
    bvid: bvid,
    service: _service,
    auth: _auth,
    mappings: widget.mappings,
    episodeQuery: widget.episodeQuery,
    subjectTitle: widget.subjectTitle,
    bangumiSubjectId: widget.bangumiSubjectId,
  );

  Future<void> _search(String keyword, {int page = 1}) async {
    if (_loading || _openingVideo) return;
    FocusScope.of(context).unfocus();
    if (page == 1 && _resultsScroll.hasClients) _resultsScroll.jumpTo(0);
    setState(() {
      _loading = true;
      _error = '';
      if (page == 1) {
        _searchKeyword = keyword;
        _hits = <BilibiliSearchHit>[];
        _page = 0;
        _totalPages = 0;
      }
    });
    try {
      final BilibiliSearchPage result = await _service.searchVideos(
        keyword,
        page: page,
      );
      if (!mounted) return;
      final Map<String, BilibiliSearchHit> unique = <String, BilibiliSearchHit>{
        if (page > 1)
          for (final hit in _hits) hit.bvid: hit,
        for (final hit in result.videos) hit.bvid: hit,
      };
      setState(() {
        _hits = unique.values.toList();
        _page = result.page;
        _totalPages = result.totalPages;
        if (_hits.isEmpty) _error = '没有找到视频，请调整关键词。';
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _chooseAlias() {
    final List<String> aliases = <String>{
      widget.subjectTitle.trim(),
      ...widget.aliases.map((name) => name.trim()),
      ...?widget.episodeQuery?.aliases.map((name) => name.trim()),
    }.where((name) => name.isNotEmpty).toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final name in aliases)
              ListTile(
                title: Text(name),
                trailing: _input.text.trim() == name
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _input.text = name;
                  unawaited(_search(name));
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _results(bool busy) {
    if (_hits.isEmpty) {
      return Center(
        child: _loading
            ? const CircularProgressIndicator()
            : const Text('输入视频链接直接播放，或用关键词查找视频。'),
      );
    }
    return ListView.builder(
      key: const ValueKey<String>('bilibili-search-results'),
      controller: _resultsScroll,
      itemCount: _hits.length + 1,
      itemBuilder: (context, index) {
        if (index == _hits.length) {
          return _page < _totalPages
              ? TextButton(
                  onPressed: busy
                      ? null
                      : () => _search(_searchKeyword, page: _page + 1),
                  child: const Text('加载更多'),
                )
              : const SizedBox(height: 20);
        }
        final hit = _hits[index];
        final String seconds = (hit.duration.inSeconds % 60).toString().padLeft(
          2,
          '0',
        );
        return ListTile(
          key: ValueKey<String>(hit.bvid),
          title: Text(hit.title),
          subtitle: Text('${hit.author} · ${hit.duration.inMinutes}:$seconds'),
          trailing: const Icon(Icons.chevron_right),
          enabled: !busy,
          onTap: () => _openVideo(hit.bvid),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.initialBvid != null) return _details(widget.initialBvid!);
    final bool busy = _loading || _openingVideo;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool hasAliases =
        widget.aliases.isNotEmpty ||
        (widget.episodeQuery?.aliases.isNotEmpty ?? false);
    final Widget body = SafeArea(
      top: !widget.embedded,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (widget.embedded)
                  Align(
                    alignment: Alignment.centerRight,
                    child: BilibiliAccountButton(auth: _auth, enabled: !busy),
                  ),
                if (!widget.embedded && widget.episodeQuery != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${widget.episodeQuery!.subjectTitle} · ${widget.episodeQuery!.episodeLabel}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _input,
                        enabled: !busy,
                        autocorrect: false,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          labelText: '视频链接、BV 号或关键词',
                          hintText: '输入 BV 号或搜索番剧、视频',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onSubmitted: (_) => _openInput(),
                      ),
                    ),
                    if (hasAliases) ...<Widget>[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: busy ? null : _chooseAlias,
                        child: const Text('别名'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: busy ? null : _openInput,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: Text(_loading ? '正在搜索…' : '打开或搜索'),
                ),
                const SizedBox(height: 8),
                Text(
                  '画质以账号当前可用的播放选项为准。',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                if (_error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error, style: TextStyle(color: colors.error)),
                  ),
                Expanded(child: _results(busy)),
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('B站视频'),
        actions: <Widget>[BilibiliAccountButton(auth: _auth, enabled: !busy)],
      ),
      body: body,
    );
  }
}

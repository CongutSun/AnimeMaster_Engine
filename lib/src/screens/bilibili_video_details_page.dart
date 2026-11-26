import 'dart:async';

import 'package:flutter/material.dart';

import '../managers/download_manager.dart';
import '../models/bilibili_video.dart';
import '../models/online_episode_source.dart';
import '../models/playable_media.dart';
import '../repositories/bilibili_episode_mapping_repository.dart';
import '../services/bilibili_auth_service.dart';
import '../services/bilibili_video_service.dart';
import '../utils/bilibili_episode_matcher.dart';
import '../utils/cached_media_playback.dart';
import '../widgets/bilibili_account_button.dart';
import '../widgets/bilibili_part_list.dart';
import 'download_center_page.dart';
import 'video_player_page.dart';

class BilibiliVideoDetailsPage extends StatefulWidget {
  final String bvid;
  final BilibiliVideoService service;
  final BilibiliAuthService auth;
  final BilibiliEpisodeMappingRepository? mappings;
  final OnlineEpisodeQuery? episodeQuery;
  final String subjectTitle;
  final int bangumiSubjectId;

  const BilibiliVideoDetailsPage({
    super.key,
    required this.bvid,
    required this.service,
    required this.auth,
    this.mappings,
    this.episodeQuery,
    this.subjectTitle = '',
    this.bangumiSubjectId = 0,
  });

  @override
  State<BilibiliVideoDetailsPage> createState() =>
      _BilibiliVideoDetailsPageState();
}

class _BilibiliVideoDetailsPageState extends State<BilibiliVideoDetailsPage> {
  BilibiliVideo? _video;
  bool _loading = false;
  int? _openingCid;
  int? _recommendedCid;
  String _recommendation = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  String _message(Object error) => error is BilibiliVideoException
      ? error.message
      : error is BilibiliAuthException
      ? error.message
      : '操作失败，请稍后重试。';

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      await widget.auth.initialize();
      if (!mounted) return;
      final BilibiliVideo video = await widget.service.loadVideo(widget.bvid);
      if (!mounted) return;
      BilibiliPart? recommendation;
      String reason = '';
      final OnlineEpisodeQuery? query = widget.episodeQuery;
      if (query != null) {
        final saved =
            await (widget.mappings ?? BilibiliEpisodeMappingRepository.instance)
                .find(query);
        if (saved?.bvid == video.bvid) {
          for (final part in video.parts) {
            if (part.cid == saved!.cid) {
              recommendation = part;
              reason = '上次选择';
              break;
            }
          }
        }
        recommendation ??= BilibiliEpisodeMatcher.suggest(video, query);
        if (recommendation != null && reason.isEmpty) reason = '集数匹配建议';
      }
      if (!mounted) return;
      setState(() {
        _video = video;
        _recommendedCid = recommendation?.cid;
        _recommendation = recommendation == null && query != null
            ? '没有唯一的集数匹配，请手动选择分 P。'
            : recommendation == null
            ? ''
            : '$reason：${recommendation.label}，请选择后播放。';
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _play(BilibiliPart part) async {
    final BilibiliVideo? video = _video;
    if (video == null || _openingCid != null || _loading) return;
    setState(() {
      _openingCid = part.cid;
      _error = '';
    });
    try {
      final task = DownloadManager().taskFor('bili_${video.bvid}_${part.cid}');
      PlayableMedia media = task != null && await task.hasCompleteFile()
          ? (await CachedMediaPlayback.prepare(task)).media
          : await widget.service.resolvePart(video, part);
      if (!mounted) return;
      final OnlineEpisodeQuery? query = widget.episodeQuery;
      if (query != null) {
        media = media.withEpisodeContext(
          subjectTitle: query.subjectTitle,
          episodeLabel: query.episodeLabel,
          bangumiSubjectId: query.bangumiSubjectId,
          bangumiEpisodeId: query.bangumiEpisodeId,
        );
        await (widget.mappings ?? BilibiliEpisodeMappingRepository.instance)
            .save(query, bvid: video.bvid, cid: part.cid);
      } else if (widget.subjectTitle.isNotEmpty) {
        media = media.withEpisodeContext(
          subjectTitle: widget.subjectTitle,
          episodeLabel: '',
          bangumiSubjectId: widget.bangumiSubjectId,
          bangumiEpisodeId: 0,
        );
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              VideoPlayerPage(media: media, bilibiliService: widget.service),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _openingCid = null);
    }
  }

  Widget _cacheButton(BilibiliVideo video, BilibiliPart part) {
    final manager = DownloadManager();
    final task = manager.taskFor('bili_${video.bvid}_${part.cid}');
    final complete = task?.isCompleted == true;
    final busy = task != null && !complete && !manager.isPaused(task.hash);
    return IconButton(
      tooltip: complete
          ? '播放离线缓存'
          : busy
          ? manager.bilibiliStatus(task)
          : '缓存 ${part.label}',
      icon: Icon(
        complete
            ? Icons.offline_pin
            : busy
            ? Icons.downloading
            : Icons.download_outlined,
      ),
      onPressed: complete
          ? () => _play(part)
          : busy
          ? null
          : () async {
              final query = widget.episodeQuery;
              try {
                await manager.cacheBilibiliPart(
                  video,
                  part,
                  subjectTitle: query?.subjectTitle ?? widget.subjectTitle,
                  episodeLabel: query?.episodeLabel ?? '',
                  bangumiSubjectId:
                      query?.bangumiSubjectId ?? widget.bangumiSubjectId,
                  bangumiEpisodeId: query?.bangumiEpisodeId ?? 0,
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('P${part.page} 已加入缓存队列'),
                    action: SnackBarAction(
                      label: '下载中心',
                      onPressed: () {
                        if (mounted) {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => const DownloadCenterPage(),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                );
              } catch (error) {
                if (mounted) setState(() => _error = _message(error));
              }
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final BilibiliVideo? video = _video;
    final OnlineEpisodeQuery? query = widget.episodeQuery;
    final String contextTitle = query == null
        ? widget.subjectTitle
        : '${query.subjectTitle} · ${query.episodeLabel}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频详情'),
        actions: <Widget>[
          BilibiliAccountButton(
            auth: widget.auth,
            enabled: !_loading && _openingCid == null,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (contextTitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        contextTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (video != null) ...<Widget>[
                    Text(
                      video.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        video.bvid,
                        '${video.parts.length} 个分 P',
                        if (!video.allowsDownload) '未开放离线缓存',
                      ].join(' · '),
                    ),
                    const SizedBox(height: 8),
                    if (_recommendation.isNotEmpty) Text(_recommendation),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: DownloadManager(),
                        builder: (_, _) => BilibiliPartList(
                          video: video,
                          openingCid: _openingCid,
                          recommendedCid: _recommendedCid,
                          onSelected: _play,
                          cacheButton: video.allowsDownload
                              ? (part) => _cacheButton(video, part)
                              : null,
                        ),
                      ),
                    ),
                  ] else if (_loading)
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新读取'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

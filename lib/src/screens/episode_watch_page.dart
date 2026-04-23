import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../api/bangumi_api.dart';
import '../managers/download_manager.dart';
import '../models/download_task_info.dart';
import '../models/online_episode_source.dart';
import '../models/playable_media.dart';
import '../services/online_episode_source_service.dart';
import '../utils/cached_media_playback.dart';
import '../utils/media_duration_probe.dart';
import '../utils/task_title_parser.dart';
import 'video_player_page.dart';

class EpisodeWatchPage extends StatefulWidget {
  final int animeId;
  final String initialName;
  final Map<String, dynamic>? detailData;
  final List<Map<String, dynamic>> episodes;
  final Map<String, dynamic> initialEpisode;
  final int currentProgress;
  final Future<void> Function(int episodeNumber)? onSetProgress;

  const EpisodeWatchPage({
    super.key,
    required this.animeId,
    required this.initialName,
    required this.detailData,
    required this.episodes,
    required this.initialEpisode,
    required this.currentProgress,
    this.onSetProgress,
  });

  @override
  State<EpisodeWatchPage> createState() => _EpisodeWatchPageState();
}

class _EpisodeWatchPageState extends State<EpisodeWatchPage>
    with SingleTickerProviderStateMixin {
  late final Player _player;
  late final VideoController _controller;
  late final TabController _tabController;
  final List<StreamSubscription<dynamic>> _playerSubscriptions =
      <StreamSubscription<dynamic>>[];
  final ValueNotifier<List<OnlineEpisodeSourceResult>> _onlineSourcesNotifier =
      ValueNotifier<List<OnlineEpisodeSourceResult>>(
        <OnlineEpisodeSourceResult>[],
      );
  final ValueNotifier<bool> _onlineSourceSearchingNotifier =
      ValueNotifier<bool>(false);

  Map<String, dynamic> _episode = <String, dynamic>{};
  Future<List<Map<String, String>>>? _commentsFuture;
  CachedPlaybackSession? _cachedSession;
  PlayableMedia? _activeMedia;
  DownloadTaskInfo? _activeTask;
  OnlineEpisodeQuery? _activeQuery;
  StreamSubscription<List<OnlineEpisodeSourceResult>>? _onlineSubscription;
  List<OnlineEpisodeSourceResult> _onlineSources =
      <OnlineEpisodeSourceResult>[];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _durationFallback = Duration.zero;
  Duration? _dragPosition;
  bool _isSearchingOnline = false;
  bool _isPreparingMedia = false;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isFullscreenRouteOpen = false;
  bool _showInlineControls = true;
  String _statusText = '正在准备播放...';
  String _dataSourceName = '自动选择';
  int _durationProbeSerial = 0;

  @override
  void initState() {
    super.initState();
    _player = Player(
      configuration: const PlayerConfiguration(bufferSize: 96 * 1024 * 1024),
    );
    _controller = VideoController(_player);
    _tabController = TabController(length: 2, vsync: this);
    _playerSubscriptions
      ..add(
        _player.stream.playing.listen((bool value) {
          if (!mounted) {
            return;
          }
          setState(() => _isPlaying = value);
        }),
      )
      ..add(
        _player.stream.buffering.listen((bool value) {
          if (!mounted) {
            return;
          }
          setState(() => _isBuffering = value);
        }),
      )
      ..add(
        _player.stream.position.listen((Duration value) {
          if (!mounted || _dragPosition != null) {
            return;
          }
          setState(() => _position = value);
        }),
      )
      ..add(
        _player.stream.duration.listen((Duration value) {
          if (!mounted) {
            return;
          }
          setState(() {
            _duration =
                value <= Duration.zero && _durationFallback > Duration.zero
                ? _durationFallback
                : value;
          });
        }),
      );
    unawaited(_selectEpisode(widget.initialEpisode, preferCache: true));
  }

  @override
  void dispose() {
    unawaited(_onlineSubscription?.cancel());
    _cachedSession?.streamServer?.stop();
    for (final StreamSubscription<dynamic> subscription
        in _playerSubscriptions) {
      subscription.cancel();
    }
    _onlineSourcesNotifier.dispose();
    _onlineSourceSearchingNotifier.dispose();
    _tabController.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _selectEpisode(
    Map<String, dynamic> episode, {
    required bool preferCache,
  }) async {
    await _onlineSubscription?.cancel();
    _cachedSession?.streamServer?.stop();
    _cachedSession = null;
    await _player.pause();
    await _player.stop();

    final OnlineEpisodeQuery query = _buildOnlineEpisodeQuery(episode);
    final int episodeId = _episodeId(episode);
    _durationProbeSerial += 1;
    if (mounted) {
      setState(() {
        _episode = episode;
        _activeQuery = query;
        _activeMedia = null;
        _activeTask = null;
        _onlineSources = <OnlineEpisodeSourceResult>[];
        _onlineSourcesNotifier.value = <OnlineEpisodeSourceResult>[];
        _commentsFuture = episodeId > 0
            ? BangumiApi.getEpisodeComments(episodeId)
            : Future<List<Map<String, String>>>.value(<Map<String, String>>[]);
        _isPreparingMedia = true;
        _isSearchingOnline = false;
        _onlineSourceSearchingNotifier.value = false;
        _statusText = '正在准备播放...';
        _dataSourceName = '自动选择';
        _position = Duration.zero;
        _duration = Duration.zero;
        _durationFallback = Duration.zero;
        _dragPosition = null;
        _showInlineControls = true;
      });
    }

    final List<DownloadTaskInfo> cachedTasks = _findCachedEpisodeTasks(episode);
    _startOnlineSearch(
      query,
      autoPlayFirst: !preferCache || cachedTasks.isEmpty,
    );

    if (preferCache && cachedTasks.isNotEmpty) {
      await _playCachedTask(cachedTasks.first);
      return;
    }

    if (mounted) {
      setState(() {
        _isPreparingMedia = cachedTasks.isEmpty;
        _statusText = cachedTasks.isEmpty ? '正在查找在线播放源...' : _statusText;
      });
    }
  }

  void _startOnlineSearch(
    OnlineEpisodeQuery query, {
    required bool autoPlayFirst,
  }) {
    bool opened = false;
    _isSearchingOnline = true;
    _onlineSourceSearchingNotifier.value = true;
    _onlineSubscription = OnlineEpisodeSourceService()
        .searchStream(query)
        .listen(
          (List<OnlineEpisodeSourceResult> results) {
            if (!mounted) {
              return;
            }
            setState(() {
              _onlineSources = results;
              _isSearchingOnline = true;
              _onlineSourcesNotifier.value = results;
              _onlineSourceSearchingNotifier.value = true;
            });
            if (autoPlayFirst && !opened && results.isNotEmpty) {
              opened = true;
              unawaited(_playOnlineSource(_selectBestOnlineSource(results)));
            }
          },
          onDone: () {
            if (!mounted) {
              return;
            }
            setState(() {
              _isSearchingOnline = false;
              _onlineSourceSearchingNotifier.value = false;
              if (_activeMedia == null) {
                _isPreparingMedia = false;
                _statusText = '未找到可播放的视频源';
              }
            });
          },
          onError: (Object error) {
            if (!mounted) {
              return;
            }
            setState(() {
              _isSearchingOnline = false;
              _onlineSourceSearchingNotifier.value = false;
              if (_activeMedia == null) {
                _isPreparingMedia = false;
                _statusText = '在线播放源搜索失败：$error';
              }
            });
          },
        );
  }

  Future<void> _playCachedTask(DownloadTaskInfo task) async {
    if (mounted) {
      setState(() {
        _isPreparingMedia = true;
        _statusText = '正在打开本地缓存...';
      });
    }

    try {
      final CachedPlaybackSession session = await CachedMediaPlayback.prepare(
        task,
      );
      _cachedSession?.streamServer?.stop();
      _cachedSession = session;
      _activeTask = task;
      await _openMedia(
        _withCurrentEpisodeContext(session.media),
        sourceName: '本地缓存',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPreparingMedia = false;
        _statusText = '本地缓存播放失败：$error';
      });
    }
  }

  Future<void> _playOnlineSource(OnlineEpisodeSourceResult source) async {
    final OnlineEpisodeQuery? query = _activeQuery;
    if (query == null || source.mediaUrl.trim().isEmpty) {
      return;
    }
    _cachedSession?.streamServer?.stop();
    _cachedSession = null;
    _activeTask = null;

    final PlayableMedia media = PlayableMedia(
      title: source.title.trim().isNotEmpty
          ? source.title.trim()
          : '${query.subjectTitle} ${query.episodeLabel}'.trim(),
      url: source.mediaUrl,
      headers: source.headers,
      subjectTitle: query.subjectTitle,
      episodeLabel: query.episodeLabel,
      bangumiSubjectId: query.bangumiSubjectId,
      bangumiEpisodeId: query.bangumiEpisodeId,
      onlineQuery: query,
      onlineEpisodes: _buildOnlineEpisodeQueries(query),
      onlineSources: _onlineSources,
    );
    await _openMedia(media, sourceName: source.sourceName);
  }

  PlayableMedia _withCurrentEpisodeContext(PlayableMedia media) {
    final OnlineEpisodeQuery? query = _activeQuery;
    return PlayableMedia(
      title: media.title,
      url: media.url,
      headers: media.headers,
      isLocal: media.isLocal,
      localFilePath: media.localFilePath,
      subjectTitle: media.subjectTitle.trim().isNotEmpty
          ? media.subjectTitle
          : (query?.subjectTitle ?? ''),
      episodeLabel: media.episodeLabel.trim().isNotEmpty
          ? media.episodeLabel
          : (query?.episodeLabel ?? ''),
      bangumiSubjectId: media.bangumiSubjectId > 0
          ? media.bangumiSubjectId
          : widget.animeId,
      bangumiEpisodeId: media.bangumiEpisodeId > 0
          ? media.bangumiEpisodeId
          : (query?.bangumiEpisodeId ?? 0),
      onlineQuery: query,
      onlineEpisodes: query == null
          ? const <OnlineEpisodeQuery>[]
          : _buildOnlineEpisodeQueries(query),
      onlineSources: _onlineSources,
    );
  }

  Future<void> _openMedia(
    PlayableMedia media, {
    required String sourceName,
  }) async {
    final int probeSerial = ++_durationProbeSerial;
    if (mounted) {
      setState(() {
        _isPreparingMedia = true;
        _statusText = '正在加载视频...';
        _position = Duration.zero;
        _duration = Duration.zero;
        _durationFallback = Duration.zero;
        _dragPosition = null;
      });
    }
    await _player.open(Media(media.url, httpHeaders: media.headers));
    unawaited(_probeDurationForMedia(media, serial: probeSerial));
    if (!mounted) {
      return;
    }
    setState(() {
      _activeMedia = media;
      _dataSourceName = sourceName;
      _isPreparingMedia = false;
      _statusText = '';
    });
  }

  Duration get _displayDuration {
    if (_duration > Duration.zero) {
      return _duration;
    }
    return _durationFallback;
  }

  Future<void> _probeDurationForMedia(
    PlayableMedia media, {
    required int serial,
  }) async {
    final Duration? probed = await MediaDurationProbe.probeHttpDuration(
      media.url,
      headers: media.headers,
    );
    if (!mounted || serial != _durationProbeSerial || probed == null) {
      return;
    }
    setState(() {
      _durationFallback = probed;
      if (_duration <= Duration.zero) {
        _duration = probed;
      }
    });
  }

  Future<void> _openFullscreen() async {
    final PlayableMedia? media = _activeMedia;
    if (media == null) {
      return;
    }
    final CachedPlaybackSession? session = _cachedSession;
    if (mounted) {
      setState(() => _isFullscreenRouteOpen = true);
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (BuildContext context) => VideoPlayerPage(
          media: media,
          streamServer: session?.streamServer,
          externalPlayer: _player,
          externalController: _controller,
          onMediaChanged: _applyFullscreenMediaUpdate,
          preferLandscapeOnOpen: true,
        ),
      ),
    );
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!mounted) {
      return;
    }
    setState(() => _isFullscreenRouteOpen = false);
  }

  void _applyFullscreenMediaUpdate(PlayableMedia media) {
    if (!mounted) {
      return;
    }
    final OnlineEpisodeQuery? query = media.onlineQuery;
    final Map<String, dynamic>? matchedEpisode = _findEpisodeForQuery(query);
    final String sourceName = _resolveSourceNameForMedia(media);
    setState(() {
      _activeMedia = media;
      _activeTask = media.isLocal || media.url.startsWith('http://127.0.0.1:')
          ? _activeTask
          : null;
      _activeQuery = query ?? _activeQuery;
      if (media.onlineSources.isNotEmpty) {
        _onlineSources = media.onlineSources;
        _onlineSourcesNotifier.value = media.onlineSources;
      }
      _dataSourceName = sourceName;
      if (matchedEpisode != null && !_isCurrentEpisode(matchedEpisode)) {
        _episode = matchedEpisode;
        final int episodeId = _episodeId(matchedEpisode);
        _commentsFuture = episodeId > 0
            ? BangumiApi.getEpisodeComments(episodeId)
            : Future<List<Map<String, String>>>.value(<Map<String, String>>[]);
      }
    });
  }

  Map<String, dynamic>? _findEpisodeForQuery(OnlineEpisodeQuery? query) {
    if (query == null) {
      return null;
    }
    for (final Map<String, dynamic> episode in widget.episodes) {
      final int episodeId = _episodeId(episode);
      final int episodeNumber = _episodeNumber(episode);
      if (query.bangumiEpisodeId > 0 && episodeId == query.bangumiEpisodeId) {
        return episode;
      }
      if (query.episodeNumber > 0 && episodeNumber == query.episodeNumber) {
        return episode;
      }
    }
    return null;
  }

  String _resolveSourceNameForMedia(PlayableMedia media) {
    if (media.isLocal || media.url.startsWith('http://127.0.0.1:')) {
      return '本地缓存';
    }
    final Iterable<OnlineEpisodeSourceResult> candidates =
        <OnlineEpisodeSourceResult>[...media.onlineSources, ..._onlineSources];
    for (final OnlineEpisodeSourceResult source in candidates) {
      if (source.mediaUrl == media.url) {
        return source.sourceName;
      }
    }
    return _dataSourceName;
  }

  Future<void> _showSourceSheet() async {
    final List<DownloadTaskInfo> cachedTasks = _findCachedEpisodeTasks(
      _episode,
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.66,
          minChildSize: 0.36,
          maxChildSize: 0.86,
          builder: (BuildContext context, ScrollController controller) {
            return ValueListenableBuilder<List<OnlineEpisodeSourceResult>>(
              valueListenable: _onlineSourcesNotifier,
              builder:
                  (
                    BuildContext context,
                    List<OnlineEpisodeSourceResult> sources,
                    Widget? child,
                  ) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: _onlineSourceSearchingNotifier,
                      builder: (BuildContext context, bool searching, _) {
                        final List<
                          MapEntry<String, List<OnlineEpisodeSourceResult>>
                        >
                        groups = _groupOnlineSources(sources).entries.toList()
                          ..sort((
                            MapEntry<String, List<OnlineEpisodeSourceResult>> a,
                            MapEntry<String, List<OnlineEpisodeSourceResult>> b,
                          ) {
                            final OnlineEpisodeSourceResult left =
                                a.value.first;
                            final OnlineEpisodeSourceResult right =
                                b.value.first;
                            if (left.verified != right.verified) {
                              return right.verified ? 1 : -1;
                            }
                            return right.score.compareTo(left.score);
                          });

                        return ListView(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 22),
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                const Expanded(
                                  child: Text(
                                    '更换数据源',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (searching)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              searching
                                  ? '正在继续解析，已找到 ${sources.length} 条可播线路'
                                  : '本地 ${cachedTasks.length} 个 · 在线 ${sources.length} 条',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            if (cachedTasks.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 12),
                              const _SourceSectionTitle(title: '本地缓存'),
                              ...cachedTasks.map(
                                (DownloadTaskInfo task) => _CachedSourceTile(
                                  task: task,
                                  selected: _activeTask?.hash == task.hash,
                                  onTap: () {
                                    Navigator.pop(context);
                                    unawaited(_playCachedTask(task));
                                  },
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            const _SourceSectionTitle(title: '在线播放'),
                            if (groups.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 26,
                                ),
                                child: Center(
                                  child: Text(
                                    searching ? '正在解析在线源...' : '暂无可用在线源',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                ),
                              )
                            else
                              ...groups.map(
                                (
                                  MapEntry<
                                    String,
                                    List<OnlineEpisodeSourceResult>
                                  >
                                  group,
                                ) => _OnlineSourceGroupCard(
                                  groupName: group.key,
                                  sources: group.value,
                                  activeMediaUrl: _activeMedia?.url ?? '',
                                  onSelected:
                                      (OnlineEpisodeSourceResult source) {
                                        Navigator.pop(context);
                                        unawaited(_playOnlineSource(source));
                                      },
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
            );
          },
        );
      },
    );
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  void _toggleInlineControls() {
    if (!mounted) {
      return;
    }
    setState(() {
      _showInlineControls = !_showInlineControls;
    });
  }

  void _handleInlineDoubleTap() {
    unawaited(_togglePlayPause());
  }

  OnlineEpisodeSourceResult _selectBestOnlineSource(
    List<OnlineEpisodeSourceResult> results,
  ) {
    final List<OnlineEpisodeSourceResult> sorted = results.toList()
      ..sort((OnlineEpisodeSourceResult a, OnlineEpisodeSourceResult b) {
        if (a.verified != b.verified) {
          return b.verified ? 1 : -1;
        }
        final int byScore = b.score.compareTo(a.score);
        if (byScore != 0) {
          return byScore;
        }
        return a.title.length.compareTo(b.title.length);
      });
    return sorted.first;
  }

  int _episodeNumber(Map<String, dynamic> episode) {
    final dynamic ep = episode['ep'] ?? episode['sort'];
    if (ep is int) {
      return ep;
    }
    if (ep is num) {
      return ep.round();
    }
    return int.tryParse(ep?.toString() ?? '') ?? 0;
  }

  int _episodeId(Map<String, dynamic> episode) {
    return int.tryParse(episode['id']?.toString() ?? '') ?? 0;
  }

  String _episodePlainTitle(Map<String, dynamic> episode) {
    final String nameCn = episode['name_cn']?.toString().trim() ?? '';
    final String name = episode['name']?.toString().trim() ?? '';
    return nameCn.isNotEmpty ? nameCn : name;
  }

  String _episodeTitle(Map<String, dynamic> episode) {
    final int number = _episodeNumber(episode);
    final String title = _stripRedundantEpisodePrefix(
      _episodePlainTitle(episode),
      number,
    );
    if (title.isEmpty) {
      return number > 0 ? '第$number集' : '未命名剧集';
    }
    return title;
  }

  String _stripRedundantEpisodePrefix(String title, int episodeNumber) {
    if (episodeNumber <= 0 || title.isEmpty) {
      return title;
    }
    final String padded = episodeNumber.toString().padLeft(2, '0');
    final List<RegExp> patterns = <RegExp>[
      RegExp('^第\\s*0?$episodeNumber\\s*[集话話]\\s*[:：.．、-]?\\s*'),
      RegExp('^0?$episodeNumber\\s*[:：.．、-]+\\s*'),
      RegExp('^0?$episodeNumber\\s+(?=\\D)'),
      RegExp('^$padded\\s*[:：.．、-]?\\s*'),
    ];
    for (final RegExp pattern in patterns) {
      final String stripped = title.replaceFirst(pattern, '').trim();
      if (stripped != title && stripped.isNotEmpty) {
        return stripped;
      }
    }
    return title;
  }

  String _episodeDescription(Map<String, dynamic> episode) {
    return episode['desc']?.toString().trim() ?? '';
  }

  String _subjectDisplayName() {
    final String originalName =
        widget.detailData?['name']?.toString().trim() ?? widget.initialName;
    final String cnName =
        widget.detailData?['name_cn']?.toString().trim() ?? widget.initialName;
    return cnName.isEmpty ? originalName : cnName;
  }

  List<String> _extractAliases(String cnName, String originalName) {
    final Set<String> aliases = <String>{
      if (cnName.isNotEmpty) cnName,
      if (originalName.isNotEmpty) originalName,
    };
    if (widget.detailData?['infobox'] is List) {
      for (final Object? item in widget.detailData!['infobox'] as List) {
        if (item is Map && item['key'] == '别名') {
          final Object? value = item['value'];
          if (value is List) {
            aliases.addAll(
              value.whereType<Map>().map((Map value) => value['v'].toString()),
            );
          } else if (value is String) {
            aliases.add(value);
          }
        }
      }
    }
    return aliases.where((String value) => value.trim().isNotEmpty).toList();
  }

  OnlineEpisodeQuery _buildOnlineEpisodeQuery(Map<String, dynamic> episode) {
    final String originalName =
        widget.detailData?['name']?.toString().trim() ?? '';
    final String cnName =
        widget.detailData?['name_cn']?.toString().trim() ?? '';
    return OnlineEpisodeQuery(
      bangumiSubjectId: widget.animeId,
      bangumiEpisodeId: _episodeId(episode),
      subjectTitle: _subjectDisplayName(),
      aliases: _extractAliases(cnName, originalName),
      episodeNumber: _episodeNumber(episode),
      episodeTitle: _episodePlainTitle(episode),
    );
  }

  List<OnlineEpisodeQuery> _buildOnlineEpisodeQueries(
    OnlineEpisodeQuery fallback,
  ) {
    final Map<String, OnlineEpisodeQuery> queries =
        <String, OnlineEpisodeQuery>{};
    for (final Map<String, dynamic> episode in widget.episodes) {
      final OnlineEpisodeQuery query = _buildOnlineEpisodeQuery(episode);
      final String key = query.bangumiEpisodeId > 0
          ? 'id:${query.bangumiEpisodeId}'
          : 'ep:${query.episodeNumber}';
      queries[key] = query;
    }
    if (queries.isEmpty) {
      queries['fallback'] = fallback;
    }
    return queries.values.toList()..sort(
      (OnlineEpisodeQuery a, OnlineEpisodeQuery b) =>
          a.episodeNumber.compareTo(b.episodeNumber),
    );
  }

  List<DownloadTaskInfo> _findCachedEpisodeTasks(Map<String, dynamic> episode) {
    final int episodeId = _episodeId(episode);
    final int episodeNumber = _episodeNumber(episode);
    final List<DownloadTaskInfo> tasks = DownloadManager().allTasks
        .where(
          (DownloadTaskInfo task) =>
              _matchesSubject(task) &&
              _matchesEpisode(task, episodeId, episodeNumber),
        )
        .toList();
    tasks.sort(
      (DownloadTaskInfo a, DownloadTaskInfo b) => _cachedTaskScore(
        b,
        episodeId,
      ).compareTo(_cachedTaskScore(a, episodeId)),
    );
    return tasks;
  }

  bool _matchesSubject(DownloadTaskInfo task) {
    if (task.bangumiSubjectId == widget.animeId) {
      return true;
    }
    final String originalName = widget.detailData?['name']?.toString() ?? '';
    final String cnName = widget.detailData?['name_cn']?.toString() ?? '';
    final Set<String> aliases = _extractAliases(cnName, originalName)
        .map((String value) => value.trim().toLowerCase())
        .where((String value) => value.isNotEmpty)
        .toSet();
    final String taskText =
        '${task.subjectTitle} ${task.title} ${task.targetPath}'.toLowerCase();
    return aliases.any(taskText.contains);
  }

  bool _matchesEpisode(
    DownloadTaskInfo task,
    int episodeId,
    int episodeNumber,
  ) {
    if (episodeId > 0 && task.bangumiEpisodeId == episodeId) {
      return true;
    }
    if (task.bangumiEpisodeId > 0 && episodeId > 0) {
      return false;
    }
    if (episodeNumber <= 0) {
      return false;
    }
    final int? taskEpisode = TaskTitleParser.extractEpisodeNumber(
      '${task.episodeLabel} ${task.title} ${task.targetPath}',
    );
    return taskEpisode == episodeNumber;
  }

  int _cachedTaskScore(DownloadTaskInfo task, int episodeId) {
    int score = 0;
    if (episodeId > 0 && task.bangumiEpisodeId == episodeId) {
      score += 100;
    }
    if (task.bangumiSubjectId == widget.animeId) {
      score += 60;
    }
    if (task.isCompleted) {
      score += 20;
    }
    if (task.targetSize > 0) {
      score += 10;
    }
    return score;
  }

  bool _isCurrentEpisode(Map<String, dynamic> episode) {
    final int currentId = _episodeId(_episode);
    final int nextId = _episodeId(episode);
    if (currentId > 0 && nextId > 0) {
      return currentId == nextId;
    }
    return _episodeNumber(_episode) == _episodeNumber(episode);
  }

  @override
  Widget build(BuildContext context) {
    final int episodeNumber = _episodeNumber(_episode);
    final String title = _episodeTitle(_episode);
    final String description = _episodeDescription(_episode);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 54,
        titleSpacing: 0,
        title: Text(
          _subjectDisplayName(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, height: 1.12),
        ),
      ),
      body: Column(
        children: <Widget>[
          _EmbeddedEpisodePlayer(
            controller: _controller,
            detached: _isFullscreenRouteOpen,
            isPreparing: _isPreparingMedia,
            isBuffering: _isBuffering,
            statusText: _statusText,
            isPlaying: _isPlaying,
            position: _dragPosition ?? _position,
            duration: _displayDuration,
            showControls: _showInlineControls,
            onToggleControls: _toggleInlineControls,
            onTogglePlay: _togglePlayPause,
            onDoubleTap: _handleInlineDoubleTap,
            onSeek: (Duration value) async {
              setState(() => _dragPosition = value);
              await _player.seek(value);
              if (mounted) {
                setState(() {
                  _position = value;
                  _dragPosition = null;
                });
              }
            },
            onFullscreen: _openFullscreen,
          ),
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              tabs: const <Widget>[
                Tab(text: '详情'),
                Tab(text: '评论'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: <Widget>[
                ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                  children: <Widget>[
                    Text(
                      _subjectDisplayName(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            episodeNumber > 0
                                ? '${episodeNumber.toString().padLeft(2, '0')}  $title'
                                : title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '把进度更新到本集',
                          onPressed:
                              episodeNumber > 0 && widget.onSetProgress != null
                              ? () => unawaited(
                                  widget.onSetProgress!(episodeNumber),
                                )
                              : null,
                          icon: const Icon(Icons.check_circle_outline_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _SourceCard(
                      sourceName: _dataSourceName,
                      episodeTitle: title,
                      isSearchingOnline: _isSearchingOnline,
                      onlineCount: _onlineSources.length,
                      cachedCount: _findCachedEpisodeTasks(_episode).length,
                      onChange: _showSourceSheet,
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: <Widget>[
                        const Text(
                          '剧集列表',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '看到 ${widget.currentProgress} · 共 ${widget.episodes.length} 话',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 86,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.episodes.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const SizedBox(width: 10),
                        itemBuilder: (BuildContext context, int index) {
                          final Map<String, dynamic> episode =
                              widget.episodes[index];
                          return _EpisodeStripCard(
                            title: _episodeTitle(episode),
                            episodeNumber: _episodeNumber(episode),
                            selected: _isCurrentEpisode(episode),
                            onTap: () => unawaited(
                              _selectEpisode(episode, preferCache: true),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '剧情介绍',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description.isEmpty ? '暂无本集简介。' : description,
                      style: const TextStyle(height: 1.55),
                    ),
                  ],
                ),
                _EpisodeCommentsView(commentsFuture: _commentsFuture),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmbeddedEpisodePlayer extends StatelessWidget {
  final VideoController controller;
  final bool detached;
  final bool isPreparing;
  final bool isBuffering;
  final String statusText;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final bool showControls;
  final VoidCallback onToggleControls;
  final VoidCallback onTogglePlay;
  final VoidCallback onDoubleTap;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onFullscreen;

  const _EmbeddedEpisodePlayer({
    required this.controller,
    required this.detached,
    required this.isPreparing,
    required this.isBuffering,
    required this.statusText,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.showControls,
    required this.onToggleControls,
    required this.onTogglePlay,
    required this.onDoubleTap,
    required this.onSeek,
    required this.onFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(
            color: Colors.black,
            child: detached
                ? const SizedBox.expand()
                : Video(controller: controller, controls: NoVideoControls),
          ),
          if (isPreparing || statusText.isNotEmpty)
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.45),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (isPreparing)
                      const CircularProgressIndicator(color: Colors.white),
                    if (statusText.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          statusText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleControls,
              onDoubleTap: onDoubleTap,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !showControls,
              child: AnimatedOpacity(
                opacity: showControls ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: _InlinePlayerBar(
                  isPlaying: isPlaying,
                  isBuffering: isBuffering,
                  position: position,
                  duration: duration,
                  onTogglePlay: onTogglePlay,
                  onSeek: onSeek,
                  onFullscreen: onFullscreen,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlinePlayerBar extends StatelessWidget {
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onFullscreen;

  const _InlinePlayerBar({
    required this.isPlaying,
    required this.isBuffering,
    required this.position,
    required this.duration,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    final int maxMs = duration.inMilliseconds <= 0
        ? 1
        : duration.inMilliseconds;
    final double value = position.inMilliseconds.clamp(0, maxMs).toDouble();

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.transparent, Color.fromARGB(185, 0, 0, 0)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
        child: Row(
          children: <Widget>[
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onTogglePlay,
              color: Colors.white,
              icon: isBuffering
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.5,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 10,
                  ),
                ),
                child: Slider(
                  value: value,
                  min: 0,
                  max: maxMs.toDouble(),
                  activeColor: Colors.white,
                  inactiveColor: Colors.white30,
                  onChanged: (double next) =>
                      onSeek(Duration(milliseconds: next.round())),
                ),
              ),
            ),
            Text(
              '${_formatInlineDuration(position)} / ${_formatInlineDuration(duration)}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onFullscreen,
              color: Colors.white,
              icon: const Icon(Icons.fullscreen_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatInlineDuration(Duration value) {
  final int totalSeconds = value.inSeconds;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  final int hours = totalSeconds ~/ 3600;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class _SourceCard extends StatelessWidget {
  final String sourceName;
  final String episodeTitle;
  final bool isSearchingOnline;
  final int onlineCount;
  final int cachedCount;
  final VoidCallback onChange;

  const _SourceCard({
    required this.sourceName,
    required this.episodeTitle,
    required this.isSearchingOnline,
    required this.onlineCount,
    required this.cachedCount,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surfaceContainerHighest.withValues(alpha: 0.72),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onChange,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: colors.primary.withValues(alpha: 0.12),
                    child: Icon(
                      Icons.hub_rounded,
                      size: 18,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          '数据源',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Text(
                          sourceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: onChange,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('换源'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                episodeTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                '本地缓存 $cachedCount 个 · 在线源 $onlineCount 个${isSearchingOnline ? ' · 搜索中' : ''}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CachedSourceTile extends StatelessWidget {
  final DownloadTaskInfo task;
  final bool selected;
  final VoidCallback onTap;

  const _CachedSourceTile({
    required this.task,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Icon(
          task.isCompleted
              ? Icons.download_done_rounded
              : Icons.downloading_rounded,
        ),
        title: Text(
          task.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          task.displaySubtitle.isEmpty ? task.targetPath : task.displaySubtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: selected ? const Icon(Icons.check_rounded) : null,
        onTap: onTap,
      ),
    );
  }
}

class _OnlineSourceGroupCard extends StatelessWidget {
  final String groupName;
  final List<OnlineEpisodeSourceResult> sources;
  final String activeMediaUrl;
  final ValueChanged<OnlineEpisodeSourceResult> onSelected;

  const _OnlineSourceGroupCard({
    required this.groupName,
    required this.sources,
    required this.activeMediaUrl,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final OnlineEpisodeSourceResult first = sources.first;
    final String tier = _onlineSourceTierLabel(first);
    final Color tierColor = _onlineSourceTierColor(colors, tier);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: tierColor.withValues(alpha: 0.13),
                  child: Text(
                    groupName.trim().isEmpty
                        ? '?'
                        : groupName.trim().substring(0, 1),
                    style: TextStyle(
                      color: tierColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    groupName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _SourceTierPill(label: tier, color: tierColor),
                const SizedBox(width: 8),
                Text(
                  '${sources.length} 线',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List<Widget>.generate(sources.length, (int index) {
                final OnlineEpisodeSourceResult source = sources[index];
                final bool selected = source.mediaUrl == activeMediaUrl;
                return ChoiceChip(
                  selected: selected,
                  avatar: Icon(
                    selected ? Icons.check_rounded : Icons.play_arrow_rounded,
                    size: 17,
                  ),
                  label: Text(_onlineSourceLineLabel(source, index)),
                  onSelected: (_) => onSelected(source),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceTierPill extends StatelessWidget {
  final String label;
  final Color color;

  const _SourceTierPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

Map<String, List<OnlineEpisodeSourceResult>> _groupOnlineSources(
  List<OnlineEpisodeSourceResult> sources,
) {
  final Map<String, List<OnlineEpisodeSourceResult>> grouped =
      <String, List<OnlineEpisodeSourceResult>>{};
  for (final OnlineEpisodeSourceResult source in sources) {
    grouped.putIfAbsent(source.sourceName, () => <OnlineEpisodeSourceResult>[]);
    grouped[source.sourceName]!.add(source);
  }
  for (final List<OnlineEpisodeSourceResult> items in grouped.values) {
    items.sort((OnlineEpisodeSourceResult a, OnlineEpisodeSourceResult b) {
      if (a.verified != b.verified) {
        return b.verified ? 1 : -1;
      }
      return b.score.compareTo(a.score);
    });
  }
  return grouped;
}

String _onlineSourceLineLabel(OnlineEpisodeSourceResult source, int index) {
  final String prefix = source.verified ? '已探测 · ' : '';
  final RegExpMatch? macLine = RegExp(
    r'/sid/(\d+)/nid/\d+',
  ).firstMatch(source.pageUrl);
  if (macLine != null) {
    return '$prefix${macLine.group(1)} 号线';
  }

  final RegExpMatch? ageLine = RegExp(
    r'/play/\d+/(\d+)/\d+',
  ).firstMatch(source.pageUrl);
  if (ageLine != null) {
    return '$prefix线路 ${ageLine.group(1)}';
  }

  if (source.sourceName.toLowerCase().contains('anime1')) {
    return '${prefix}Anime1';
  }
  return '$prefix线路 ${index + 1}';
}

String _onlineSourceTierLabel(OnlineEpisodeSourceResult source) {
  final String normalized = source.sourceName.toLowerCase();
  if (normalized.contains('omofun') ||
      normalized.contains('age') ||
      normalized.contains('anime1')) {
    return '优先';
  }
  if (normalized.contains('风铃') ||
      normalized.contains('稀饭') ||
      normalized.contains('mutefun') ||
      normalized.contains('七色') ||
      normalized.contains('5弹幕')) {
    return '可用';
  }
  return '备用';
}

Color _onlineSourceTierColor(ColorScheme colors, String tier) {
  return switch (tier) {
    '优先' => colors.primary,
    '可用' => Colors.green.shade700,
    _ => colors.onSurfaceVariant,
  };
}

class _EpisodeStripCard extends StatelessWidget {
  final String title;
  final int episodeNumber;
  final bool selected;
  final VoidCallback onTap;

  const _EpisodeStripCard({
    required this.title,
    required this.episodeNumber,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 116,
      child: Material(
        color: selected
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (selected)
                      Icon(Icons.bar_chart_rounded, color: colors.primary),
                    if (selected) const SizedBox(width: 6),
                    Text(
                      episodeNumber > 0
                          ? episodeNumber.toString().padLeft(2, '0')
                          : '?',
                      style: TextStyle(
                        color: selected ? colors.primary : colors.onSurface,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeCommentsView extends StatelessWidget {
  final Future<List<Map<String, String>>>? commentsFuture;

  const _EpisodeCommentsView({required this.commentsFuture});

  @override
  Widget build(BuildContext context) {
    final Future<List<Map<String, String>>>? future = commentsFuture;
    if (future == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return FutureBuilder<List<Map<String, String>>>(
      future: future,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<List<Map<String, String>>> snapshot,
          ) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final List<Map<String, String>> comments =
                snapshot.data ?? <Map<String, String>>[];
            if (comments.isEmpty) {
              return const Center(
                child: Text('暂无本集讨论', style: TextStyle(color: Colors.grey)),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              itemCount: comments.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                final Map<String, String> comment = comments[index];
                final bool isReply = comment['type'] == 'reply';
                final int floor = _episodeCommentFloor(comments, index);
                return _EpisodeCommentCard(
                  comment: comment,
                  isReply: isReply,
                  floorLabel: isReply ? '' : '#$floor',
                );
              },
            );
          },
    );
  }
}

int _episodeCommentFloor(List<Map<String, String>> comments, int index) {
  int floor = 0;
  for (int i = 0; i <= index; i++) {
    if (comments[i]['type'] != 'reply') {
      floor += 1;
    }
  }
  return floor;
}

class _EpisodeCommentCard extends StatelessWidget {
  final Map<String, String> comment;
  final bool isReply;
  final String floorLabel;

  const _EpisodeCommentCard({
    required this.comment,
    required this.isReply,
    required this.floorLabel,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String author = (comment['author'] ?? '').trim().isEmpty
        ? '网络用户'
        : comment['author']!.trim();
    final String time = (comment['time'] ?? '').trim();
    final String content = (comment['content'] ?? '').trim();

    return Padding(
      padding: EdgeInsets.only(left: isReply ? 28 : 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isReply
              ? colors.surfaceContainerHighest.withValues(alpha: 0.42)
              : colors.surface,
          borderRadius: BorderRadius.circular(isReply ? 12 : 16),
          border: Border.all(
            color: isReply
                ? colors.primary.withValues(alpha: 0.22)
                : colors.outlineVariant.withValues(alpha: 0.34),
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (isReply)
                Container(
                  width: 3,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          if (floorLabel.isNotEmpty) ...<Widget>[
                            Text(
                              floorLabel,
                              style: TextStyle(
                                color: isReply ? colors.primary : Colors.grey,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: isReply ? 13 : 14,
                              ),
                            ),
                          ),
                          if (time.isNotEmpty)
                            Text(
                              time,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        content,
                        style: TextStyle(
                          height: 1.45,
                          color: isReply ? colors.onSurfaceVariant : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceSectionTitle extends StatelessWidget {
  final String title;

  const _SourceSectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../coordinator/episode_coordinator.dart';
import '../managers/download_manager.dart';
import '../models/dandanplay_models.dart';
import '../models/download_task_info.dart';
import '../models/playable_media.dart';
import '../providers/settings_provider.dart';
import '../services/animeko_danmaku_service.dart';
import '../services/dandanplay_service.dart';
import '../utils/torrent_stream_server.dart';

class VideoPlayerPage extends StatefulWidget {
  final PlayableMedia media;
  final TorrentStreamServer? streamServer;

  const VideoPlayerPage({super.key, required this.media, this.streamServer});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  static const List<double> _supportedRates = <double>[
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  late final Player _player;
  late final VideoController _controller;
  final EpisodeCoordinator _coordinator = EpisodeCoordinator();
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  late final bool _isMagnet;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _dragPosition;
  double _rate = 1.0;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _showControls = false;
  bool _isFullscreenLocked = false;
  Timer? _controlsTimer;
  Timer? _danmakuTicker;
  PlayableMedia? _activeMedia;
  DateTime? _lastManualSeekAt;
  List<DandanplayComment> _danmakuComments = <DandanplayComment>[];
  List<_ActiveDanmakuItem> _activeDanmaku = <_ActiveDanmakuItem>[];
  String _danmakuStatusText = '';
  bool _danmakuEnabled = true;
  bool _isDanmakuLoading = false;
  int _nextDanmakuIndex = 0;
  int _danmakuSerial = 0;
  int _danmakuSeed = 0;

  @override
  void initState() {
    super.initState();
    _enterPlayerMode();

    _player = Player();
    _controller = VideoController(_player);
    _isMagnet = widget.media.url.toLowerCase().startsWith('magnet:');

    _subscriptions.add(
      _player.stream.position.listen((Duration value) {
        if (!mounted) {
          return;
        }
        final Duration normalized = _normalizeIncomingPosition(value);
        setState(() {
          _position = normalized;
        });
      }),
    );
    _subscriptions.add(
      _player.stream.duration.listen((Duration value) {
        if (!mounted) {
          return;
        }
        final Duration normalized = _normalizeIncomingDuration(value);
        setState(() {
          _duration = normalized;
        });
      }),
    );
    _subscriptions.add(
      _player.stream.rate.listen((double value) {
        if (!mounted) {
          return;
        }
        setState(() {
          _rate = value;
        });
      }),
    );
    _subscriptions.add(
      _player.stream.playing.listen((bool value) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isPlaying = value;
          if (!value) {
            _showControls = true;
          }
        });
        if (value) {
          _scheduleControlsAutoHide();
        } else {
          _cancelControlsAutoHide();
        }
      }),
    );
    _subscriptions.add(
      _player.stream.buffering.listen((bool value) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isBuffering = value;
          if (value) {
            _showControls = true;
          }
        });
        if (value) {
          _cancelControlsAutoHide();
        } else if (_isPlaying) {
          _scheduleControlsAutoHide();
        }
      }),
    );

    if (_isMagnet) {
      _coordinator.addListener(_onStateChanged);
      _coordinator.loadEpisode(
        widget.media.url,
        preferredTitle: widget.media.title,
        subjectTitle: widget.media.subjectTitle,
        episodeLabel: widget.media.episodeLabel,
      );
    } else {
      _openMedia(widget.media);
    }
  }

  Future<void> _enterPlayerMode() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _exitPlayerMode() async {
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _onStateChanged() {
    if (_coordinator.currentState == PlaybackState.readyToPlay &&
        _coordinator.currentMedia != null) {
      _openMedia(_coordinator.currentMedia!);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openMedia(PlayableMedia media) async {
    if (mounted) {
      setState(() {
        _position = Duration.zero;
        _duration = Duration.zero;
        _dragPosition = null;
        _lastManualSeekAt = null;
      });
    }
    await _player.open(Media(media.url, httpHeaders: media.headers));
    if (_rate != 1.0) {
      await _player.setRate(_rate);
    }
    _activeMedia = media;
    await _prepareDanmakuForMedia(media);
    if (mounted) {
      setState(() {
        _showControls = false;
      });
    }
  }

  void _toggleControls() {
    if (!mounted) {
      return;
    }
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _scheduleControlsAutoHide();
    } else {
      _cancelControlsAutoHide();
    }
  }

  void _scheduleControlsAutoHide() {
    _cancelControlsAutoHide();
    if (!_isPlaying || _isBuffering || !_showControls) {
      return;
    }
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _cancelControlsAutoHide() {
    _controlsTimer?.cancel();
    _controlsTimer = null;
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
    _scheduleControlsAutoHide();
  }

  Future<void> _setRate(double value) async {
    await _player.setRate(value);
    if (mounted) {
      setState(() {
        _rate = value;
      });
    }
    _scheduleControlsAutoHide();
  }

  Future<void> _seekRelative(int seconds) async {
    final Duration base = _dragPosition ?? _position;
    final Duration target = base + Duration(seconds: seconds);
    final Duration max = _duration > Duration.zero ? _duration : target;
    final Duration clamped = target < Duration.zero
        ? Duration.zero
        : (target > max ? max : target);
    _lastManualSeekAt = DateTime.now();
    await _player.seek(clamped);
    if (mounted) {
      setState(() {
        _position = clamped;
        _dragPosition = null;
      });
    }
    _resyncDanmakuCursor(clamped);
    _scheduleControlsAutoHide();
  }

  Future<void> _prepareDanmakuForMedia(
    PlayableMedia media, {
    bool forceReload = false,
  }) async {
    final int serial = ++_danmakuSerial;
    _cancelDanmakuTicker();
    _activeDanmaku = <_ActiveDanmakuItem>[];
    _nextDanmakuIndex = 0;
    _danmakuSeed = 0;

    final SettingsProvider settings = context.read<SettingsProvider>();

    if (!forceReload &&
        _activeMedia?.url == media.url &&
        _danmakuComments.isNotEmpty) {
      _resyncDanmakuCursor(_effectivePosition);
      _startDanmakuTicker();
      return;
    }

    if (mounted) {
      setState(() {
        _danmakuComments = <DandanplayComment>[];
        _activeDanmaku = <_ActiveDanmakuItem>[];
        _isDanmakuLoading = true;
        _danmakuStatusText = settings.hasDandanplayCredentials
            ? '正在匹配弹幕...'
            : '正在加载 Animeko 公益弹幕...';
      });
    }

    try {
      final DandanplayLoadResult result = await _loadBestAvailableDanmaku(
        media,
        settings,
      );

      if (!mounted || serial != _danmakuSerial) {
        return;
      }

      setState(() {
        _danmakuComments = result.comments;
        _isDanmakuLoading = false;
        _danmakuStatusText = result.comments.isEmpty
            ? '未找到弹幕'
            : '已加载 ${result.comments.length} 条弹幕';
      });

      _resyncDanmakuCursor(_effectivePosition);
      if (_danmakuEnabled && result.comments.isNotEmpty) {
        _startDanmakuTicker();
      }
    } catch (error) {
      if (!mounted || serial != _danmakuSerial) {
        return;
      }
      setState(() {
        _danmakuComments = <DandanplayComment>[];
        _activeDanmaku = <_ActiveDanmakuItem>[];
        _isDanmakuLoading = false;
        _danmakuStatusText = _friendlyDanmakuError(error);
      });
      if (settings.hasDandanplayCredentials &&
          _shouldSuggestManualDanmakuMatch(error)) {
        _showManualDanmakuMatchPrompt();
      }
    }
  }

  Future<DandanplayLoadResult> _loadBestAvailableDanmaku(
    PlayableMedia media,
    SettingsProvider settings,
  ) async {
    Object? dandanplayError;

    if (settings.hasDandanplayCredentials) {
      try {
        return await _createDandanplayService(settings).loadDanmaku(
          displayTitle: media.title,
          localFilePath: _resolveLocalFilePath(media),
          subjectTitle: _resolveSubjectTitle(media),
          episodeLabel: _resolveEpisodeLabel(media),
        );
      } catch (error) {
        dandanplayError = error;
      }
    }

    try {
      return await AnimekoDanmakuService().loadDanmaku(
        displayTitle: media.title,
        subjectTitle: _resolveSubjectTitle(media),
        episodeLabel: _resolveEpisodeLabel(media),
        bangumiSubjectId: media.bangumiSubjectId,
        bangumiEpisodeId: media.bangumiEpisodeId,
      );
    } catch (_) {
      if (dandanplayError != null) {
        throw dandanplayError;
      }
      rethrow;
    }
  }

  DandanplayService _createDandanplayService(SettingsProvider settings) {
    return DandanplayService(
      appId: settings.dandanplayAppId,
      appSecret: settings.dandanplayAppSecret,
    );
  }

  String _resolveLocalFilePath(PlayableMedia media) {
    if (media.localFilePath.trim().isNotEmpty) {
      return media.localFilePath.trim();
    }
    if (media.isLocal && File(media.url).existsSync()) {
      return media.url;
    }
    return '';
  }

  String _resolveSubjectTitle(PlayableMedia media) {
    if (media.subjectTitle.trim().isNotEmpty) {
      return media.subjectTitle.trim();
    }
    return media.title;
  }

  String _resolveEpisodeLabel(PlayableMedia media) {
    if (media.episodeLabel.trim().isNotEmpty) {
      return media.episodeLabel.trim();
    }
    return '';
  }

  String _friendlyDanmakuError(Object error) {
    final String message = error
        .toString()
        .replaceFirst('Exception: ', '')
        .trim();
    return message.isEmpty ? '弹幕加载失败' : message;
  }

  bool _shouldSuggestManualDanmakuMatch(Object error) {
    final String message = error.toString();
    return message.contains('匹配') || message.contains('节目');
  }

  void _showManualDanmakuMatchPrompt() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('自动匹配失败，可以手动搜索并指定弹幕剧集。'),
        action: SnackBarAction(
          label: '手动匹配',
          onPressed: _showManualDanmakuSearchSheet,
        ),
      ),
    );
  }

  void _cancelDanmakuTicker() {
    _danmakuTicker?.cancel();
    _danmakuTicker = null;
  }

  void _startDanmakuTicker() {
    _cancelDanmakuTicker();
    if (!_danmakuEnabled || _danmakuComments.isEmpty) {
      return;
    }
    _danmakuTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _pumpDanmaku();
    });
  }

  void _pumpDanmaku() {
    if (!_danmakuEnabled ||
        !_isPlaying ||
        _isBuffering ||
        _danmakuComments.isEmpty) {
      return;
    }

    final Duration threshold = _position + const Duration(milliseconds: 350);
    final List<_ActiveDanmakuItem> pending = <_ActiveDanmakuItem>[];

    while (_nextDanmakuIndex < _danmakuComments.length &&
        _danmakuComments[_nextDanmakuIndex].appearAt <= threshold) {
      final DandanplayComment comment = _danmakuComments[_nextDanmakuIndex];
      if (comment.appearAt + const Duration(seconds: 1) >= _position) {
        pending.add(
          _ActiveDanmakuItem(
            id: DateTime.now().microsecondsSinceEpoch + _nextDanmakuIndex,
            comment: comment,
            lane: _resolveDanmakuLane(comment.mode),
          ),
        );
      }
      _nextDanmakuIndex++;
    }

    if (pending.isEmpty || !mounted) {
      return;
    }

    setState(() {
      _activeDanmaku = <_ActiveDanmakuItem>[..._activeDanmaku, ...pending];
    });
  }

  int _resolveDanmakuLane(int mode) {
    final bool isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final int laneCount = mode == 1 ? (isLandscape ? 8 : 5) : 2;
    final int lane = _danmakuSeed % laneCount;
    _danmakuSeed++;
    return lane;
  }

  void _resyncDanmakuCursor(Duration position) {
    _cancelDanmakuTicker();
    _nextDanmakuIndex = 0;
    while (_nextDanmakuIndex < _danmakuComments.length &&
        _danmakuComments[_nextDanmakuIndex].appearAt <
            position - const Duration(milliseconds: 300)) {
      _nextDanmakuIndex++;
    }
    if (mounted) {
      setState(() {
        _activeDanmaku = <_ActiveDanmakuItem>[];
      });
    }
    if (_danmakuEnabled) {
      _startDanmakuTicker();
    }
  }

  Future<void> _toggleDanmaku() async {
    final bool nextEnabled = !_danmakuEnabled;
    setState(() {
      _danmakuEnabled = nextEnabled;
    });

    if (!nextEnabled) {
      _cancelDanmakuTicker();
      if (mounted) {
        setState(() {
          _activeDanmaku = <_ActiveDanmakuItem>[];
        });
      }
      _scheduleControlsAutoHide();
      return;
    }

    final PlayableMedia? media = _activeMedia;
    if (_danmakuComments.isEmpty && media != null) {
      await _prepareDanmakuForMedia(media, forceReload: true);
    } else {
      _resyncDanmakuCursor(_effectivePosition);
    }

    if (mounted && _danmakuStatusText.isNotEmpty && _danmakuComments.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_danmakuStatusText)));
    }
    _scheduleControlsAutoHide();
  }

  Future<void> _showManualDanmakuSearchSheet() async {
    final PlayableMedia? media = _activeMedia;
    if (media == null) {
      return;
    }

    final SettingsProvider settings = context.read<SettingsProvider>();
    if (!settings.hasDandanplayCredentials) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('弹弹play 手动匹配需要 AppId/AppSecret；当前会自动尝试 Animeko 公益弹幕。'),
        ),
      );
      return;
    }

    final DandanplayService service = _createDandanplayService(settings);
    final String initialAnimeKeyword = service.buildSuggestedAnimeKeyword(
      displayTitle: media.title,
      subjectTitle: _resolveSubjectTitle(media),
    );
    final String initialEpisodeKeyword = service.buildSuggestedEpisodeKeyword(
      displayTitle: media.title,
      episodeLabel: _resolveEpisodeLabel(media),
    );

    _cancelControlsAutoHide();
    await _showPlayerPanel<void>(
      portraitHeightFactor: 0.82,
      landscapeHeightFactor: 0.82,
      maxLandscapeWidth: 460,
      builder: (BuildContext panelContext) => _DanmakuMatchSheet(
        initialAnimeKeyword: initialAnimeKeyword,
        initialEpisodeKeyword: initialEpisodeKeyword,
        onSearch: (String animeKeyword, String episodeKeyword) {
          return service.searchEpisodeCandidates(
            animeKeyword: animeKeyword,
            episodeKeyword: episodeKeyword,
          );
        },
        onSelected: (DandanplayMatchResult match) async {
          Navigator.of(panelContext).pop();
          await _applyManualDanmakuMatch(match);
        },
      ),
    );
    _scheduleControlsAutoHide();
  }

  Future<void> _applyManualDanmakuMatch(DandanplayMatchResult match) async {
    final PlayableMedia? media = _activeMedia;
    if (media == null) {
      return;
    }

    final SettingsProvider settings = context.read<SettingsProvider>();
    final DandanplayService service = _createDandanplayService(settings);
    service.rememberManualMatch(
      displayTitle: media.title,
      localFilePath: _resolveLocalFilePath(media),
      subjectTitle: _resolveSubjectTitle(media),
      episodeLabel: _resolveEpisodeLabel(media),
      match: match,
    );

    final int serial = ++_danmakuSerial;
    _cancelDanmakuTicker();
    if (mounted) {
      setState(() {
        _isDanmakuLoading = true;
        _danmakuStatusText = '正在加载手动匹配的弹幕...';
        _danmakuComments = <DandanplayComment>[];
        _activeDanmaku = <_ActiveDanmakuItem>[];
      });
    }

    try {
      final DandanplayLoadResult result = await service.loadDanmakuFromMatch(
        match,
      );
      if (!mounted || serial != _danmakuSerial) {
        return;
      }
      setState(() {
        _danmakuComments = result.comments;
        _isDanmakuLoading = false;
        _danmakuEnabled = true;
        _danmakuStatusText = result.comments.isEmpty
            ? '已匹配到剧集，但当前没有可显示的弹幕。'
            : '已手动匹配：${result.match.displayTitle}';
      });
      _resyncDanmakuCursor(_effectivePosition);
      if (_danmakuComments.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_danmakuStatusText)));
      }
    } catch (error) {
      if (!mounted || serial != _danmakuSerial) {
        return;
      }
      setState(() {
        _danmakuComments = <DandanplayComment>[];
        _isDanmakuLoading = false;
        _danmakuStatusText = _friendlyDanmakuError(error);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_danmakuStatusText)));
    }
  }

  Future<void> _showRateSheet() async {
    _cancelControlsAutoHide();
    await _showPlayerPanel<void>(
      portraitHeightFactor: 0.42,
      landscapeHeightFactor: 0.56,
      maxLandscapeWidth: 260,
      maxPortraitWidth: 320,
      builder: (BuildContext dialogContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _PlayerPanelHeader(
            icon: Icons.speed_rounded,
            title: '\u500d\u901f',
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: _supportedRates.map((double value) {
                final bool selected = (_rate - value).abs() < 0.01;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    selected ? Icons.radio_button_checked : Icons.speed,
                  ),
                  title: Text(
                    '${value.toStringAsFixed(value == 1.0 ? 1 : 2)}x',
                  ),
                  onTap: () async {
                    Navigator.pop(dialogContext);
                    await _setRate(value);
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
    _scheduleControlsAutoHide();
  }

  Future<T?> _showPlayerPanel<T>({
    required WidgetBuilder builder,
    required double portraitHeightFactor,
    required double landscapeHeightFactor,
    required double maxLandscapeWidth,
    double maxPortraitWidth = 560,
  }) {
    final bool isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.18),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder:
          (
            BuildContext dialogContext,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) {
            final MediaQueryData media = MediaQuery.of(dialogContext);
            final double availableWidth =
                media.size.width - media.padding.horizontal - 24;
            final double availableHeight =
                media.size.height - media.padding.vertical - 24;
            final double width = isLandscape
                ? math.min(maxLandscapeWidth, availableWidth * 0.5)
                : math.min(maxPortraitWidth, availableWidth);
            final double height = math.min(
              availableHeight,
              media.size.height *
                  (isLandscape ? landscapeHeightFactor : portraitHeightFactor),
            );

            return SafeArea(
              child: Align(
                alignment: isLandscape
                    ? Alignment.centerRight
                    : Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    12,
                    12,
                    isLandscape ? 12 : 20,
                  ),
                  child: Material(
                    color: Theme.of(dialogContext).colorScheme.surface,
                    elevation: 20,
                    shadowColor: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: builder(dialogContext),
                    ),
                  ),
                ),
              ),
            );
          },
      transitionBuilder:
          (
            BuildContext dialogContext,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            Widget child,
          ) {
            final Animation<Offset> offset =
                Tween<Offset>(
                  begin: isLandscape
                      ? const Offset(0.12, 0)
                      : const Offset(0, 0.08),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                );

            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: offset, child: child),
            );
          },
    );
  }

  PlayableMedia _buildMediaFromTask(DownloadTaskInfo task) {
    final File localFile = File(task.targetPath);
    if (task.isCompleted && localFile.existsSync()) {
      return PlayableMedia(
        title: task.displayTitle,
        url: task.targetPath,
        isLocal: true,
        localFilePath: task.targetPath,
        subjectTitle: task.subjectTitle,
        episodeLabel: task.episodeLabel,
        bangumiSubjectId: task.bangumiSubjectId,
        bangumiEpisodeId: task.bangumiEpisodeId,
      );
    }
    return PlayableMedia(
      title: task.displayTitle,
      url: task.url,
      localFilePath: task.targetPath,
      subjectTitle: task.subjectTitle,
      episodeLabel: task.episodeLabel,
      bangumiSubjectId: task.bangumiSubjectId,
      bangumiEpisodeId: task.bangumiEpisodeId,
    );
  }

  Future<void> _showCacheSelectionSheet() async {
    final List<DownloadTaskInfo> tasks = DownloadManager().allTasks.reversed
        .toList();

    if (tasks.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\u7f13\u5b58\u4e2d\u5fc3\u5f53\u524d\u6ca1\u6709\u53ef\u5207\u6362\u7684\u4efb\u52a1\u3002',
            ),
          ),
        );
      }
      return;
    }

    _cancelControlsAutoHide();
    await _showPlayerPanel<void>(
      portraitHeightFactor: 0.78,
      landscapeHeightFactor: 0.76,
      maxLandscapeWidth: 420,
      builder: (BuildContext context) => _CacheSelectionSheet(
        tasks: tasks,
        onSelected: (DownloadTaskInfo task) {
          unawaited(_replaceWithTask(task));
        },
      ),
    );
    _scheduleControlsAutoHide();
  }

  Future<void> _replaceWithTask(DownloadTaskInfo task) async {
    await DownloadManager().prepareForPlayback(task.hash);
    final File localFile = File(task.targetPath);
    TorrentStreamServer? streamServer;
    PlayableMedia media = _buildMediaFromTask(task);

    if (!task.isCompleted && task.targetSize > 0) {
      DownloadManager().prioritizePlaybackRange(
        task.hash,
        task.targetPath,
        0,
        512 * 1024,
      );
      streamServer = TorrentStreamServer(
        videoFilePath: task.targetPath,
        videoSize: task.targetSize,
        infoHash: task.hash,
      );
      final String streamUrl = await streamServer.start();
      media = PlayableMedia(
        title: task.displayTitle,
        url: streamUrl,
        localFilePath: task.targetPath,
        subjectTitle: task.subjectTitle,
        episodeLabel: task.episodeLabel,
        bangumiSubjectId: task.bangumiSubjectId,
        bangumiEpisodeId: task.bangumiEpisodeId,
      );
    } else if (task.isCompleted && localFile.existsSync()) {
      media = _buildMediaFromTask(task);
    }

    if (!mounted) {
      streamServer?.stop();
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            VideoPlayerPage(media: media, streamServer: streamServer),
      ),
    );
  }

  Future<void> _toggleFullscreenLock() async {
    _cancelControlsAutoHide();
    if (_isFullscreenLocked) {
      await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    if (mounted) {
      setState(() {
        _isFullscreenLocked = !_isFullscreenLocked;
      });
    }
    _scheduleControlsAutoHide();
  }

  String _formatDuration(Duration value) {
    final int totalSeconds = value.inSeconds;
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get _displayTitle {
    if (_isMagnet && _coordinator.currentMedia != null) {
      return _coordinator.currentMedia!.title;
    }
    return widget.media.title;
  }

  Duration get _effectivePosition => _dragPosition ?? _position;

  bool get _isStreamingPlayback {
    final String url = _activeMedia?.url ?? widget.media.url;
    return _isMagnet || url.startsWith('http://127.0.0.1:');
  }

  Duration _normalizeIncomingDuration(Duration value) {
    if (!_isStreamingPlayback || value <= Duration.zero) {
      return value;
    }
    if (_duration > Duration.zero && value < _duration) {
      return _duration;
    }
    return value;
  }

  Duration _normalizeIncomingPosition(Duration value) {
    if (!_isStreamingPlayback || _dragPosition != null) {
      return value;
    }
    final DateTime? lastManualSeekAt = _lastManualSeekAt;
    if (lastManualSeekAt != null &&
        DateTime.now().difference(lastManualSeekAt) <
            const Duration(seconds: 2)) {
      return value;
    }
    if (_position > const Duration(seconds: 5) &&
        value + const Duration(seconds: 2) < _position) {
      return _position;
    }
    return value;
  }

  void _removeDanmakuItem(int id) {
    if (!mounted) {
      return;
    }
    setState(() {
      _activeDanmaku = _activeDanmaku
          .where((_ActiveDanmakuItem item) => item.id != id)
          .toList();
    });
  }

  @override
  void dispose() {
    _cancelControlsAutoHide();
    _cancelDanmakuTicker();
    for (final StreamSubscription<dynamic> subscription in _subscriptions) {
      subscription.cancel();
    }
    if (_isMagnet) {
      _coordinator.removeListener(_onStateChanged);
      _coordinator.reset();
    }
    widget.streamServer?.stop();
    _player.dispose();
    _exitPlayerMode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool showPlayer =
        !_isMagnet || _coordinator.currentState == PlaybackState.readyToPlay;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: showPlayer ? _toggleControls : null,
              child: showPlayer
                  ? Center(
                      child: Video(
                        controller: _controller,
                        controls: NoVideoControls,
                      ),
                    )
                  : _buildStateOverlay(),
            ),
          ),
          if (showPlayer && _danmakuEnabled && _activeDanmaku.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: _DanmakuOverlay(
                  items: _activeDanmaku,
                  onCompleted: _removeDanmakuItem,
                ),
              ),
            ),
          if (showPlayer)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: _buildControlsOverlay(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControlsOverlay() {
    final bool isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final EdgeInsets bottomPadding = isLandscape
        ? const EdgeInsets.fromLTRB(16, 8, 16, 14)
        : const EdgeInsets.fromLTRB(10, 6, 10, 10);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      child: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color.fromARGB(140, 0, 0, 0),
                Color.fromARGB(20, 0, 0, 0),
                Color.fromARGB(170, 0, 0, 0),
              ],
            ),
          ),
          child: Column(
            children: <Widget>[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          _displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_isBuffering)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {},
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _RoundControlButton(
                          icon: Icons.replay_10_rounded,
                          onPressed: () => _seekRelative(-10),
                        ),
                        const SizedBox(width: 18),
                        _RoundControlButton(
                          icon: _isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 34,
                          diameter: 72,
                          onPressed: _togglePlayPause,
                        ),
                        const SizedBox(width: 18),
                        _RoundControlButton(
                          icon: Icons.forward_10_rounded,
                          onPressed: () => _seekRelative(10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Container(
                  width: double.infinity,
                  padding: bottomPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Wrap(
                        spacing: isLandscape ? 8 : 4,
                        runSpacing: isLandscape ? 4 : 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          _buildBottomAction(
                            icon: Icons.video_library_rounded,
                            label: '选集 (${DownloadManager().allTasks.length})',
                            onPressed: _showCacheSelectionSheet,
                          ),
                          _buildBottomAction(
                            icon: Icons.speed_rounded,
                            label:
                                '倍速 ${_rate.toStringAsFixed(_rate == 1.0 ? 1 : 2)}x',
                            onPressed: _showRateSheet,
                          ),
                          _buildBottomAction(
                            icon: _danmakuEnabled
                                ? Icons.subtitles_rounded
                                : Icons.subtitles_off_rounded,
                            label: _isDanmakuLoading
                                ? '弹幕加载'
                                : (_danmakuEnabled ? '弹幕' : '弹幕关'),
                            onPressed: _toggleDanmaku,
                          ),
                          _buildBottomAction(
                            icon: _isFullscreenLocked
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            label: _isFullscreenLocked ? '退出全屏' : '全屏',
                            onPressed: _toggleFullscreenLock,
                          ),
                        ],
                      ),
                      if (_danmakuStatusText.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                _danmakuStatusText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (_danmakuComments.isEmpty &&
                                !_isDanmakuLoading &&
                                _activeMedia != null &&
                                context
                                    .read<SettingsProvider>()
                                    .hasDandanplayCredentials)
                              TextButton(
                                onPressed: _showManualDanmakuSearchSheet,
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text('手动匹配'),
                              ),
                          ],
                        ),
                      ],
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                        ),
                        child: Slider(
                          value: _duration.inMilliseconds <= 0
                              ? 0
                              : _effectivePosition.inMilliseconds
                                    .clamp(0, _duration.inMilliseconds)
                                    .toDouble(),
                          min: 0,
                          max: _duration.inMilliseconds <= 0
                              ? 1
                              : _duration.inMilliseconds.toDouble(),
                          activeColor: Colors.blueAccent,
                          inactiveColor: Colors.white30,
                          onChangeStart: (_) => _cancelControlsAutoHide(),
                          onChanged: (double value) {
                            setState(() {
                              _dragPosition = Duration(
                                milliseconds: value.round(),
                              );
                            });
                          },
                          onChangeEnd: (double value) async {
                            final Duration target = Duration(
                              milliseconds: value.round(),
                            );
                            _lastManualSeekAt = DateTime.now();
                            await _player.seek(target);
                            if (mounted) {
                              setState(() {
                                _position = target;
                                _dragPosition = null;
                              });
                            }
                            _resyncDanmakuCursor(target);
                            _scheduleControlsAutoHide();
                          },
                        ),
                      ),
                      Row(
                        children: <Widget>[
                          Text(
                            _formatDuration(_effectivePosition),
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const Spacer(),
                          Text(
                            _formatDuration(_duration),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
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

  Widget _buildBottomAction({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildStateOverlay() {
    String message = '';
    bool isError = false;

    switch (_coordinator.currentState) {
      case PlaybackState.idle:
      case PlaybackState.fetching:
        message = '\u6b63\u5728\u83b7\u53d6\u79cd\u5b50\u5143\u6570\u636e...';
        break;
      case PlaybackState.resolving:
        message =
            '\u6b63\u5728\u51c6\u5907\u6587\u4ef6\u4e0e\u64ad\u653e\u94fe\u8def...';
        break;
      case PlaybackState.error:
        message = '\u64ad\u653e\u5931\u8d25\uff1a${_coordinator.errorMessage}';
        isError = true;
        break;
      case PlaybackState.readyToPlay:
        break;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!isError)
              const CircularProgressIndicator(color: Colors.greenAccent),
            if (isError)
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 48,
              ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final double diameter;
  final double size;

  const _RoundControlButton({
    required this.icon,
    required this.onPressed,
    this.diameter = 58,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }
}

class _PlayerPanelHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _PlayerPanelHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _CacheSelectionSheet extends StatefulWidget {
  final List<DownloadTaskInfo> tasks;
  final ValueChanged<DownloadTaskInfo> onSelected;

  const _CacheSelectionSheet({required this.tasks, required this.onSelected});

  @override
  State<_CacheSelectionSheet> createState() => _CacheSelectionSheetState();
}

class _CacheSelectionSheetState extends State<_CacheSelectionSheet> {
  final TextEditingController _searchController = TextEditingController();
  bool _onlyCompleted = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DownloadTaskInfo> get _filteredTasks {
    final String keyword = _searchController.text.trim().toLowerCase();
    return widget.tasks.where((DownloadTaskInfo task) {
      if (_onlyCompleted && !task.isCompleted) {
        return false;
      }
      if (keyword.isEmpty) {
        return true;
      }
      final String haystack =
          '${task.displayTitle} ${task.displaySubtitle} ${task.hash}'
              .toLowerCase();
      return haystack.contains(keyword);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final List<DownloadTaskInfo> tasks = _filteredTasks;
    final bool isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, isLandscape ? 14 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _PlayerPanelHeader(
            icon: Icons.video_library_rounded,
            title: '\u7f13\u5b58\u9009\u96c6',
          ),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText:
                  '\u641c\u7d22\u7f13\u5b58\u6807\u9898\u3001\u756a\u540d\u3001\u96c6\u6570\u6216\u54c8\u5e0c',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              FilterChip(
                label: const Text('\u53ea\u770b\u5df2\u5b8c\u6210'),
                selected: _onlyCompleted,
                onSelected: (bool value) {
                  setState(() {
                    _onlyCompleted = value;
                  });
                },
              ),
              const Spacer(),
              Text(
                '\u5171 ${tasks.length} \u9879',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: tasks.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '\u6ca1\u6709\u7b26\u5408\u6761\u4ef6\u7684\u7f13\u5b58\u4efb\u52a1\u3002',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: tasks.length,
                    separatorBuilder: (BuildContext context, int index) =>
                        const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final DownloadTaskInfo task = tasks[index];
                      final bool isCompleted = task.isCompleted;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        dense: isLandscape,
                        leading: Icon(
                          isCompleted
                              ? Icons.play_circle_fill_rounded
                              : Icons.downloading_rounded,
                          color: isCompleted ? Colors.green : Colors.blueAccent,
                        ),
                        title: Text(
                          task.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          task.displaySubtitle.isNotEmpty
                              ? task.displaySubtitle
                              : '\u4efb\u52a1\u54c8\u5e0c\uff1a${task.hash}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          isCompleted
                              ? '\u5df2\u5b8c\u6210'
                              : '\u7f13\u5b58\u4e2d',
                          style: TextStyle(
                            fontSize: 12,
                            color: isCompleted
                                ? Colors.green
                                : Colors.blueAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          widget.onSelected(task);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DanmakuMatchSheet extends StatefulWidget {
  final String initialAnimeKeyword;
  final String initialEpisodeKeyword;
  final Future<List<DandanplayMatchResult>> Function(
    String animeKeyword,
    String episodeKeyword,
  )
  onSearch;
  final Future<void> Function(DandanplayMatchResult match) onSelected;

  const _DanmakuMatchSheet({
    required this.initialAnimeKeyword,
    required this.initialEpisodeKeyword,
    required this.onSearch,
    required this.onSelected,
  });

  @override
  State<_DanmakuMatchSheet> createState() => _DanmakuMatchSheetState();
}

class _DanmakuMatchSheetState extends State<_DanmakuMatchSheet> {
  late final TextEditingController _animeController;
  late final TextEditingController _episodeController;

  bool _isSearching = false;
  bool _isSelecting = false;
  String _errorText = '';
  List<DandanplayMatchResult> _results = <DandanplayMatchResult>[];

  @override
  void initState() {
    super.initState();
    _animeController = TextEditingController(text: widget.initialAnimeKeyword);
    _episodeController = TextEditingController(
      text: widget.initialEpisodeKeyword,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialAnimeKeyword.trim().length >= 2) {
        _search();
      }
    });
  }

  @override
  void dispose() {
    _animeController.dispose();
    _episodeController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final String animeKeyword = _animeController.text.trim();
    final String episodeKeyword = _episodeController.text.trim();
    if (animeKeyword.length < 2) {
      setState(() {
        _results = <DandanplayMatchResult>[];
        _errorText = '请至少输入 2 个字符的番剧名称。';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorText = '';
    });

    try {
      final List<DandanplayMatchResult> results = await widget.onSearch(
        animeKeyword,
        episodeKeyword,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
        _errorText = results.isEmpty ? '没有搜索到可选剧集，请调整关键词。' : '';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _results = <DandanplayMatchResult>[];
        _errorText = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _select(DandanplayMatchResult match) async {
    setState(() {
      _isSelecting = true;
    });
    try {
      await widget.onSelected(match);
    } finally {
      if (mounted) {
        setState(() {
          _isSelecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _PlayerPanelHeader(
            icon: Icons.manage_search_rounded,
            title: '手动匹配弹幕',
          ),
          TextField(
            controller: _animeController,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              labelText: '番剧名称',
              hintText: '例如：药屋少女的呢喃',
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _episodeController,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              labelText: '集数关键词',
              hintText: '例如：01、12、SP、Movie',
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              FilledButton.icon(
                onPressed: _isSearching || _isSelecting ? null : _search,
                icon: _isSearching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded),
                label: const Text('搜索剧集'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _errorText.isNotEmpty
                      ? _errorText
                      : '从结果中选择正确剧集后，播放器会直接加载该弹幕。',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: _errorText.isNotEmpty
                        ? Colors.redAccent
                        : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _isSearching ? '正在搜索...' : '暂无可选剧集',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (BuildContext context, int index) =>
                        const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final DandanplayMatchResult item = _results[index];
                      return ListTile(
                        enabled: !_isSelecting,
                        leading: const Icon(Icons.subtitles_rounded),
                        title: Text(
                          item.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'episodeId: ${item.episodeId}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: _isSelecting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.chevron_right_rounded),
                        onTap: () => _select(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ActiveDanmakuItem {
  final int id;
  final DandanplayComment comment;
  final int lane;

  const _ActiveDanmakuItem({
    required this.id,
    required this.comment,
    required this.lane,
  });
}

class _DanmakuOverlay extends StatelessWidget {
  final List<_ActiveDanmakuItem> items;
  final ValueChanged<int> onCompleted;

  const _DanmakuOverlay({required this.items, required this.onCompleted});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Stack(
          clipBehavior: Clip.none,
          children: items
              .map(
                (_ActiveDanmakuItem item) => _DanmakuBullet(
                  key: ValueKey<int>(item.id),
                  item: item,
                  viewportSize: constraints.biggest,
                  onCompleted: () => onCompleted(item.id),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _DanmakuBullet extends StatefulWidget {
  final _ActiveDanmakuItem item;
  final Size viewportSize;
  final VoidCallback onCompleted;

  const _DanmakuBullet({
    super.key,
    required this.item,
    required this.viewportSize,
    required this.onCompleted,
  });

  @override
  State<_DanmakuBullet> createState() => _DanmakuBulletState();
}

class _DanmakuBulletState extends State<_DanmakuBullet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    final int durationMs = widget.item.comment.mode == 1
        ? (7000 + widget.item.comment.text.length * 80).clamp(6500, 12000)
        : 4000;
    _controller =
        AnimationController(
            vsync: this,
            duration: Duration(milliseconds: durationMs),
          )
          ..addStatusListener((AnimationStatus status) {
            if (status == AnimationStatus.completed && mounted) {
              widget.onCompleted();
            }
          })
          ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _estimateTextWidth(String text) {
    return math.max(120.0, text.runes.length * 16.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final double textWidth = _estimateTextWidth(widget.item.comment.text);
    final double laneHeight = 30;

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final int mode = widget.item.comment.mode;
        final double progress = _controller.value;
        final double top = switch (mode) {
          4 =>
            widget.viewportSize.height -
                90 -
                (widget.item.lane + 1) * laneHeight,
          5 => 12 + widget.item.lane * laneHeight,
          _ => 12 + widget.item.lane * laneHeight,
        };

        final double left = mode == 1
            ? widget.viewportSize.width -
                  (widget.viewportSize.width + textWidth + 32) * progress
            : (widget.viewportSize.width - textWidth) / 2;
        final double opacity = mode == 1
            ? 1
            : (progress < 0.15
                  ? progress / 0.15
                  : (progress > 0.85 ? (1 - progress) / 0.15 : 1));

        return Positioned(
          left: left,
          top: top,
          child: Opacity(opacity: opacity.clamp(0, 1), child: child),
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            widget.item.comment.text,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: TextStyle(
              color: Color(0xFF000000 | widget.item.comment.color),
              fontSize: 16,
              fontWeight: FontWeight.w600,
              shadows: const <Shadow>[
                Shadow(
                  color: Colors.black87,
                  blurRadius: 3,
                  offset: Offset(0.8, 0.8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

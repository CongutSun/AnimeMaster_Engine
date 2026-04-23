import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:volume_controller/volume_controller.dart';

import '../coordinator/episode_coordinator.dart';
import '../managers/download_manager.dart';
import '../models/dandanplay_models.dart';
import '../models/download_task_info.dart';
import '../models/online_episode_source.dart';
import '../models/playable_media.dart';
import '../providers/settings_provider.dart';
import '../services/animeko_danmaku_service.dart';
import '../services/dandanplay_service.dart';
import '../services/online_episode_source_service.dart';
import '../utils/media_duration_probe.dart';
import '../utils/torrent_stream_server.dart';

enum _GestureAdjustmentKind { brightness, volume }

class VideoPlayerPage extends StatefulWidget {
  final PlayableMedia media;
  final TorrentStreamServer? streamServer;
  final Player? externalPlayer;
  final VideoController? externalController;
  final ValueChanged<PlayableMedia>? onMediaChanged;
  final bool preferLandscapeOnOpen;

  const VideoPlayerPage({
    super.key,
    required this.media,
    this.streamServer,
    this.externalPlayer,
    this.externalController,
    this.onMediaChanged,
    this.preferLandscapeOnOpen = false,
  });

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
  late final bool _ownsPlayer;
  final EpisodeCoordinator _coordinator = EpisodeCoordinator();
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  late final bool _isMagnet;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _durationFallback = Duration.zero;
  Duration? _dragPosition;
  double _rate = 1.0;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _showControls = false;
  bool _isFullscreenLocked = false;
  bool _suppressControlsOnNextPause = false;
  Timer? _controlsTimer;
  Timer? _danmakuTicker;
  Timer? _progressSaveTimer;
  Timer? _gestureIndicatorTimer;
  Timer? _sliderSeekThrottle;
  PlayableMedia? _activeMedia;
  OnlineEpisodeQuery? _onlineQuery;
  List<OnlineEpisodeQuery> _onlineEpisodes = <OnlineEpisodeQuery>[];
  List<OnlineEpisodeSourceResult> _onlineSources =
      <OnlineEpisodeSourceResult>[];
  StreamSubscription<List<OnlineEpisodeSourceResult>>?
  _onlineSourceSubscription;
  final ValueNotifier<List<OnlineEpisodeSourceResult>> _onlineSourcesNotifier =
      ValueNotifier<List<OnlineEpisodeSourceResult>>(
        <OnlineEpisodeSourceResult>[],
      );
  final ValueNotifier<bool> _onlineSourceSearchingNotifier =
      ValueNotifier<bool>(false);
  bool _isOnlineSourceSearching = false;
  DateTime? _lastManualSeekAt;
  DateTime _lastProgressSavedAt = DateTime.fromMillisecondsSinceEpoch(0);
  List<DandanplayComment> _danmakuComments = <DandanplayComment>[];
  List<_ActiveDanmakuItem> _activeDanmaku = <_ActiveDanmakuItem>[];
  String _danmakuStatusText = '';
  bool _danmakuEnabled = true;
  bool _danmakuShowBackground = true;
  bool _danmakuShowStroke = true;
  bool _isDanmakuLoading = false;
  double _danmakuFontSize = 16.0;
  double _danmakuOpacity = 1.0;
  double _danmakuSpeed = 1.0;
  double _danmakuAreaRatio = 0.55;
  int _nextDanmakuIndex = 0;
  int _danmakuSerial = 0;
  int _danmakuSeed = 0;
  _GestureAdjustmentKind? _gestureAdjustmentKind;
  double _gestureStartValue = 0.5;
  double _gestureAccumulatedDy = 0;
  double _currentBrightness = 0.5;
  double _currentVolume = 0.5;
  String _gestureIndicatorText = '';
  IconData _gestureIndicatorIcon = Icons.touch_app_rounded;
  double? _gestureIndicatorProgress;
  int _durationProbeSerial = 0;

  @override
  void initState() {
    super.initState();
    _isFullscreenLocked = widget.preferLandscapeOnOpen;
    _enterPlayerMode();
    unawaited(_loadDanmakuStyle());
    unawaited(_loadGestureAdjustmentState());

    _ownsPlayer = widget.externalPlayer == null;
    _player =
        widget.externalPlayer ??
        Player(
          configuration: const PlayerConfiguration(
            bufferSize: 96 * 1024 * 1024,
          ),
        );
    _controller = widget.externalController ?? VideoController(_player);
    _isMagnet = widget.media.url.toLowerCase().startsWith('magnet:');
    _initializeOnlinePlaybackContext(widget.media);

    _subscriptions.add(
      _player.stream.position.listen((Duration value) {
        if (!mounted) {
          return;
        }
        final Duration normalized = _normalizeIncomingPosition(value);
        setState(() {
          _position = normalized;
        });
        _savePlaybackProgressThrottled();
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
          if (!value && !_suppressControlsOnNextPause) {
            _showControls = true;
          }
          if (!value) {
            _suppressControlsOnNextPause = false;
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
    } else if (_ownsPlayer) {
      _openMedia(widget.media);
    } else {
      _activeMedia = widget.media;
      unawaited(_probeDurationForMedia(widget.media));
      unawaited(_prepareDanmakuForMedia(widget.media));
    }

    _progressSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_savePlaybackProgress(force: true));
    });
  }

  Future<void> _enterPlayerMode() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (widget.preferLandscapeOnOpen) {
      await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      return;
    }
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _exitPlayerMode() async {
    if (widget.preferLandscapeOnOpen) {
      await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
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
    final int probeSerial = ++_durationProbeSerial;
    if (mounted) {
      setState(() {
        _position = Duration.zero;
        _duration = Duration.zero;
        _durationFallback = Duration.zero;
        _dragPosition = null;
        _lastManualSeekAt = null;
      });
    }
    _activeMedia = media;
    widget.onMediaChanged?.call(media);
    await _player.open(Media(media.url, httpHeaders: media.headers));
    unawaited(_probeDurationForMedia(media, serial: probeSerial));
    await _restorePlaybackProgress(media);
    if (_rate != 1.0) {
      await _player.setRate(_rate);
    }
    await _prepareDanmakuForMedia(media);
    if (mounted) {
      setState(() {
        _showControls = false;
      });
    }
  }

  bool get _hasOnlineContext =>
      _onlineQuery != null ||
      _onlineEpisodes.isNotEmpty ||
      _onlineSources.isNotEmpty;

  void _initializeOnlinePlaybackContext(PlayableMedia media) {
    _onlineQuery = media.onlineQuery;
    _onlineEpisodes = media.onlineEpisodes;
    _setOnlineSources(media.onlineSources, notifyState: false);
    if (_onlineQuery != null) {
      _startOnlineSourceSearch(_onlineQuery!, clearExisting: false);
    }
  }

  void _setOnlineSources(
    List<OnlineEpisodeSourceResult> sources, {
    bool notifyState = true,
  }) {
    final List<OnlineEpisodeSourceResult> next =
        List<OnlineEpisodeSourceResult>.unmodifiable(sources);
    _onlineSources = next;
    _onlineSourcesNotifier.value = next;
    if (notifyState && mounted) {
      setState(() {});
    }
  }

  void _setOnlineSourceSearching(bool value) {
    _isOnlineSourceSearching = value;
    _onlineSourceSearchingNotifier.value = value;
  }

  void _startOnlineSourceSearch(
    OnlineEpisodeQuery query, {
    required bool clearExisting,
    bool autoPlayFirst = false,
  }) {
    unawaited(_onlineSourceSubscription?.cancel());
    if (clearExisting) {
      _setOnlineSources(
        const <OnlineEpisodeSourceResult>[],
        notifyState: false,
      );
    }
    _onlineQuery = query;
    bool hasOpenedFirstSource = false;
    if (mounted) {
      setState(() {
        _setOnlineSourceSearching(true);
      });
    } else {
      _setOnlineSourceSearching(true);
    }

    _onlineSourceSubscription = OnlineEpisodeSourceService()
        .searchStream(query)
        .listen(
          (List<OnlineEpisodeSourceResult> results) {
            if (!mounted) {
              return;
            }
            setState(() {
              _setOnlineSources(results, notifyState: false);
            });
            if (autoPlayFirst && !hasOpenedFirstSource && results.isNotEmpty) {
              hasOpenedFirstSource = true;
              unawaited(
                _openOnlineSourceInPlayer(
                  _selectBestOnlineSource(results),
                  query,
                  preserveProgress: false,
                ),
              );
            }
          },
          onError: (Object error) {
            if (!mounted) {
              return;
            }
            setState(() {
              _setOnlineSourceSearching(false);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('在线源搜索失败：$error'),
                backgroundColor: Colors.redAccent,
              ),
            );
          },
          onDone: () {
            if (!mounted) {
              return;
            }
            setState(() {
              _setOnlineSourceSearching(false);
            });
            if (autoPlayFirst &&
                !hasOpenedFirstSource &&
                _onlineSources.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('未找到该集可直接播放的在线源。'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          },
        );
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

  PlayableMedia _buildMediaFromOnlineSource(
    OnlineEpisodeSourceResult source,
    OnlineEpisodeQuery query,
  ) {
    return PlayableMedia(
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
      onlineEpisodes: _onlineEpisodes,
      onlineSources: _onlineSources,
    );
  }

  Future<void> _openOnlineSourceInPlayer(
    OnlineEpisodeSourceResult source,
    OnlineEpisodeQuery query, {
    bool preserveProgress = true,
  }) async {
    if (source.mediaUrl.trim().isEmpty) {
      return;
    }
    if (preserveProgress) {
      await _savePlaybackProgress(force: true);
    }
    await _openMedia(_buildMediaFromOnlineSource(source, query));
    _scheduleControlsAutoHide();
  }

  Future<void> _switchOnlineEpisode(OnlineEpisodeQuery query) async {
    _cancelControlsAutoHide();
    await _savePlaybackProgress(force: true);
    await _player.pause();
    await _player.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _onlineQuery = query;
      _activeMedia = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _dragPosition = null;
      _isPlaying = false;
      _isBuffering = false;
      _setOnlineSources(
        const <OnlineEpisodeSourceResult>[],
        notifyState: false,
      );
      _showControls = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在查找 ${query.episodeLabel} 的在线源...'),
        duration: const Duration(seconds: 2),
      ),
    );
    _startOnlineSourceSearch(query, clearExisting: true, autoPlayFirst: true);
  }

  Future<void> _showOnlineSourceSheet() async {
    _cancelControlsAutoHide();
    await _showPlayerPanel<void>(
      portraitHeightFactor: 0.74,
      landscapeHeightFactor: 0.72,
      maxLandscapeWidth: 460,
      builder: (BuildContext context) => _OnlineSourceSelectionSheet(
        sourcesListenable: _onlineSourcesNotifier,
        searchingListenable: _onlineSourceSearchingNotifier,
        activeMediaUrl: _activeMedia?.url ?? '',
        onSelected: (OnlineEpisodeSourceResult source) {
          final OnlineEpisodeQuery? query = _onlineQuery;
          if (query == null) {
            return;
          }
          unawaited(_openOnlineSourceInPlayer(source, query));
        },
      ),
    );
    _scheduleControlsAutoHide();
  }

  Future<void> _showOnlineEpisodeSheet() async {
    if (_onlineEpisodes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前番剧没有可切换的在线剧集列表。')));
      return;
    }
    _cancelControlsAutoHide();
    await _showPlayerPanel<void>(
      portraitHeightFactor: 0.78,
      landscapeHeightFactor: 0.76,
      maxLandscapeWidth: 460,
      builder: (BuildContext context) => _OnlineEpisodeSelectionSheet(
        episodes: _onlineEpisodes,
        activeQuery: _onlineQuery,
        onSelected: (OnlineEpisodeQuery query) {
          unawaited(_switchOnlineEpisode(query));
        },
      ),
    );
    _scheduleControlsAutoHide();
  }

  Future<void> _restorePlaybackProgress(PlayableMedia media) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = _playbackProgressKey(media);
    final int savedPositionMs = prefs.getInt('$key.position') ?? 0;
    final int savedDurationMs = prefs.getInt('$key.duration') ?? 0;
    if (savedPositionMs < const Duration(seconds: 10).inMilliseconds) {
      return;
    }
    if (savedDurationMs > 0 &&
        savedPositionMs >
            savedDurationMs - const Duration(seconds: 20).inMilliseconds) {
      return;
    }

    final Duration restored = Duration(milliseconds: savedPositionMs);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _player.seek(restored);
    if (!mounted) {
      return;
    }
    setState(() {
      _position = restored;
      _dragPosition = null;
    });
    _resyncDanmakuCursor(restored);
  }

  void _savePlaybackProgressThrottled() {
    final DateTime now = DateTime.now();
    if (now.difference(_lastProgressSavedAt) < const Duration(seconds: 5)) {
      return;
    }
    _lastProgressSavedAt = now;
    unawaited(_savePlaybackProgress());
  }

  Future<void> _savePlaybackProgress({
    Duration? position,
    bool force = false,
  }) async {
    final PlayableMedia? media = _activeMedia;
    if (media == null) {
      return;
    }

    final Duration currentPosition = position ?? _effectivePosition;
    if (!force && currentPosition < const Duration(seconds: 5)) {
      return;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = _playbackProgressKey(media);
    await prefs.setInt('$key.position', currentPosition.inMilliseconds);
    await prefs.setInt('$key.duration', _displayDuration.inMilliseconds);
    await prefs.setInt('$key.updatedAt', DateTime.now().millisecondsSinceEpoch);
  }

  String _playbackProgressKey(PlayableMedia media) {
    final String identity = media.bangumiEpisodeId > 0
        ? 'bgm_ep:${media.bangumiEpisodeId}'
        : [
            media.localFilePath,
            media.url,
            media.subjectTitle,
            media.episodeLabel,
            media.title,
          ].where((String value) => value.trim().isNotEmpty).join('|');
    final String encoded = base64Url.encode(utf8.encode(identity));
    return 'playback_progress.$encoded';
  }

  Future<void> _loadDanmakuStyle() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _danmakuFontSize = prefs.getDouble('danmaku.fontSize') ?? 16.0;
      _danmakuOpacity = prefs.getDouble('danmaku.opacity') ?? 1.0;
      _danmakuSpeed = prefs.getDouble('danmaku.speed') ?? 1.0;
      _danmakuAreaRatio = prefs.getDouble('danmaku.areaRatio') ?? 0.55;
      _danmakuShowBackground = prefs.getBool('danmaku.showBackground') ?? true;
      _danmakuShowStroke = prefs.getBool('danmaku.showStroke') ?? true;
    });
  }

  Future<void> _saveDanmakuStyle() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('danmaku.fontSize', _danmakuFontSize);
    await prefs.setDouble('danmaku.opacity', _danmakuOpacity);
    await prefs.setDouble('danmaku.speed', _danmakuSpeed);
    await prefs.setDouble('danmaku.areaRatio', _danmakuAreaRatio);
    await prefs.setBool('danmaku.showBackground', _danmakuShowBackground);
    await prefs.setBool('danmaku.showStroke', _danmakuShowStroke);
  }

  Future<void> _loadGestureAdjustmentState() async {
    VolumeController.instance.showSystemUI = false;
    try {
      final double brightness =
          await ScreenBrightnessPlatform.instance.application;
      _currentBrightness = brightness.clamp(0.0, 1.0).toDouble();
    } catch (_) {
      _currentBrightness = 0.5;
    }

    try {
      final double volume = await VolumeController.instance.getVolume();
      _currentVolume = volume.clamp(0.0, 1.0).toDouble();
    } catch (_) {
      _currentVolume = 0.5;
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

  void _handlePlayerDoubleTap() {
    final bool willPlay = !_isPlaying;
    if (_isPlaying) {
      _suppressControlsOnNextPause = true;
      _cancelControlsAutoHide();
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    }
    unawaited(_togglePlayPause());
    _showGestureIndicator(
      icon: willPlay ? Icons.play_arrow_rounded : Icons.pause_rounded,
      text: willPlay ? '播放' : '暂停',
    );
  }

  void _handleVerticalDragStart(DragStartDetails details) {
    final double width = MediaQuery.sizeOf(context).width;
    _gestureAdjustmentKind = details.localPosition.dx < width / 2
        ? _GestureAdjustmentKind.brightness
        : _GestureAdjustmentKind.volume;
    _gestureAccumulatedDy = 0;
    _gestureStartValue = _gestureAdjustmentKind == _GestureAdjustmentKind.volume
        ? _currentVolume
        : _currentBrightness;
    _showGestureIndicatorForAdjustment(_gestureStartValue);
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    final _GestureAdjustmentKind? kind = _gestureAdjustmentKind;
    if (kind == null) {
      return;
    }
    final double height = math.max(MediaQuery.sizeOf(context).height, 1);
    _gestureAccumulatedDy += details.delta.dy;
    final double nextValue =
        (_gestureStartValue - _gestureAccumulatedDy / (height * 0.72))
            .clamp(0.0, 1.0)
            .toDouble();

    if (kind == _GestureAdjustmentKind.brightness) {
      _currentBrightness = nextValue;
      unawaited(
        ScreenBrightnessPlatform.instance.setApplicationScreenBrightness(
          nextValue,
        ),
      );
    } else {
      _currentVolume = nextValue;
      unawaited(VolumeController.instance.setVolume(nextValue));
    }
    _showGestureIndicatorForAdjustment(nextValue);
  }

  void _handleVerticalDragEnd([DragEndDetails? details]) {
    _gestureAdjustmentKind = null;
    _hideGestureIndicatorDelayed();
  }

  void _showGestureIndicatorForAdjustment(double value) {
    final bool isBrightness =
        _gestureAdjustmentKind == _GestureAdjustmentKind.brightness;
    _showGestureIndicator(
      icon: isBrightness ? Icons.brightness_6_rounded : Icons.volume_up_rounded,
      text: '${isBrightness ? '亮度' : '音量'} ${(value * 100).round()}%',
      progress: value,
      autoHide: false,
    );
  }

  void _showGestureIndicator({
    required IconData icon,
    required String text,
    double? progress,
    bool autoHide = true,
  }) {
    _gestureIndicatorTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _gestureIndicatorIcon = icon;
      _gestureIndicatorText = text;
      _gestureIndicatorProgress = progress;
    });
    if (autoHide) {
      _hideGestureIndicatorDelayed();
    }
  }

  void _hideGestureIndicatorDelayed() {
    _gestureIndicatorTimer?.cancel();
    _gestureIndicatorTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _gestureIndicatorText = '';
        _gestureIndicatorProgress = null;
      });
    });
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
    final Duration max = _displayDuration > Duration.zero
        ? _displayDuration
        : target;
    final Duration clamped = target < Duration.zero
        ? Duration.zero
        : (target > max ? max : target);
    _lastManualSeekAt = DateTime.now();
    await _player.seek(clamped);
    unawaited(_savePlaybackProgress(position: clamped, force: true));
    if (mounted) {
      setState(() {
        _position = clamped;
        _dragPosition = null;
      });
    }
    _resyncDanmakuCursor(clamped);
    _scheduleControlsAutoHide();
  }

  void _seekFromSlider(double value) {
    final Duration target = Duration(milliseconds: value.round());
    _lastManualSeekAt = DateTime.now();
    setState(() {
      _position = target;
      _dragPosition = target;
    });
    _resyncDanmakuCursor(target);

    _sliderSeekThrottle?.cancel();
    _sliderSeekThrottle = Timer(const Duration(milliseconds: 80), () {
      unawaited(_player.seek(target));
    });
  }

  Future<void> _finishSliderSeek(double value) async {
    final Duration target = Duration(milliseconds: value.round());
    _sliderSeekThrottle?.cancel();
    _sliderSeekThrottle = null;
    _lastManualSeekAt = DateTime.now();
    await _player.seek(target);
    unawaited(_savePlaybackProgress(position: target, force: true));
    if (mounted) {
      setState(() {
        _position = target;
        _dragPosition = null;
      });
    }
    _resyncDanmakuCursor(target);
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
    final int baseLaneCount = mode == 1 ? (isLandscape ? 10 : 6) : 2;
    final int laneCount = math.max(
      1,
      (baseLaneCount * (_danmakuAreaRatio / 0.55)).round(),
    );
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

  Future<void> _showDanmakuStyleSheet() async {
    _cancelControlsAutoHide();
    await _showPlayerPanel<void>(
      portraitHeightFactor: 0.62,
      landscapeHeightFactor: 0.78,
      maxLandscapeWidth: 360,
      maxPortraitWidth: 380,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setPanelState) {
            void update(VoidCallback change) {
              setState(change);
              setPanelState(() {});
              unawaited(_saveDanmakuStyle());
            }

            Widget buildSlider({
              required String label,
              required double value,
              required double min,
              required double max,
              required int divisions,
              required String display,
              required ValueChanged<double> onChanged,
              VoidCallback? afterChanged,
            }) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(display, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  Slider(
                    value: value,
                    min: min,
                    max: max,
                    divisions: divisions,
                    onChanged: (double next) {
                      update(() => onChanged(next));
                      afterChanged?.call();
                    },
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _PlayerPanelHeader(
                  icon: Icons.tune_rounded,
                  title: '弹幕样式',
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: <Widget>[
                      SwitchListTile(
                        dense: true,
                        title: const Text('弹幕开关'),
                        value: _danmakuEnabled,
                        onChanged: (bool value) {
                          update(() {
                            _danmakuEnabled = value;
                            if (!value) {
                              _activeDanmaku = <_ActiveDanmakuItem>[];
                            }
                          });
                          if (value) {
                            _resyncDanmakuCursor(_effectivePosition);
                          }
                        },
                      ),
                      SwitchListTile(
                        dense: true,
                        title: const Text('文字描边'),
                        value: _danmakuShowStroke,
                        onChanged: (bool value) =>
                            update(() => _danmakuShowStroke = value),
                      ),
                      SwitchListTile(
                        dense: true,
                        title: const Text('半透明底色'),
                        value: _danmakuShowBackground,
                        onChanged: (bool value) =>
                            update(() => _danmakuShowBackground = value),
                      ),
                      buildSlider(
                        label: '字号',
                        value: _danmakuFontSize,
                        min: 12,
                        max: 28,
                        divisions: 16,
                        display: '${_danmakuFontSize.round()} px',
                        onChanged: (double value) => _danmakuFontSize = value,
                      ),
                      buildSlider(
                        label: '透明度',
                        value: _danmakuOpacity,
                        min: 0.35,
                        max: 1.0,
                        divisions: 13,
                        display:
                            '${(_danmakuOpacity * 100).round().clamp(35, 100)}%',
                        onChanged: (double value) => _danmakuOpacity = value,
                      ),
                      buildSlider(
                        label: '速度',
                        value: _danmakuSpeed,
                        min: 0.7,
                        max: 1.6,
                        divisions: 9,
                        display: '${_danmakuSpeed.toStringAsFixed(1)}x',
                        onChanged: (double value) => _danmakuSpeed = value,
                      ),
                      buildSlider(
                        label: '显示区域',
                        value: _danmakuAreaRatio,
                        min: 0.25,
                        max: 0.9,
                        divisions: 13,
                        display:
                            '${(_danmakuAreaRatio * 100).round().clamp(25, 90)}%',
                        onChanged: (double value) {
                          _danmakuAreaRatio = value;
                        },
                        afterChanged: () =>
                            _resyncDanmakuCursor(_effectivePosition),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: OutlinedButton.icon(
                          onPressed: () {
                            update(() {
                              _danmakuFontSize = 16.0;
                              _danmakuOpacity = 1.0;
                              _danmakuSpeed = 1.0;
                              _danmakuAreaRatio = 0.55;
                              _danmakuShowBackground = true;
                              _danmakuShowStroke = true;
                            });
                            _resyncDanmakuCursor(_effectivePosition);
                          },
                          icon: const Icon(Icons.restore_rounded),
                          label: const Text('恢复默认样式'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
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
    if (widget.preferLandscapeOnOpen) {
      await _exitPlayerMode();
      if (mounted) {
        await Navigator.of(context).maybePop();
      }
      return;
    }
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
    final PlayableMedia media = (_isMagnet && _coordinator.currentMedia != null)
        ? _coordinator.currentMedia!
        : (_activeMedia ?? widget.media);
    if (media.subjectTitle.trim().isNotEmpty &&
        media.episodeLabel.trim().isNotEmpty) {
      return '${media.subjectTitle.trim()} · ${media.episodeLabel.trim()}';
    }
    if (_isMagnet && _coordinator.currentMedia != null) {
      return _coordinator.currentMedia!.title;
    }
    return media.title;
  }

  Duration get _effectivePosition => _dragPosition ?? _position;

  Duration get _displayDuration {
    if (_duration > Duration.zero) {
      return _duration;
    }
    return _durationFallback;
  }

  bool get _isStreamingPlayback {
    final String url = _activeMedia?.url ?? widget.media.url;
    return _isMagnet || url.startsWith('http://127.0.0.1:');
  }

  Duration _normalizeIncomingDuration(Duration value) {
    if (value <= Duration.zero && _durationFallback > Duration.zero) {
      return _durationFallback;
    }
    if (!_isStreamingPlayback || value <= Duration.zero) {
      return value;
    }
    if (_duration > Duration.zero && value < _duration) {
      return _duration;
    }
    return value;
  }

  Future<void> _probeDurationForMedia(
    PlayableMedia media, {
    int? serial,
  }) async {
    final int activeSerial = serial ?? ++_durationProbeSerial;
    final Duration? probed = await MediaDurationProbe.probeHttpDuration(
      media.url,
      headers: media.headers,
    );
    if (!mounted || activeSerial != _durationProbeSerial || probed == null) {
      return;
    }
    setState(() {
      _durationFallback = probed;
      if (_duration <= Duration.zero) {
        _duration = probed;
      }
    });
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
    unawaited(_savePlaybackProgress(force: true));
    unawaited(_onlineSourceSubscription?.cancel());
    unawaited(
      ScreenBrightnessPlatform.instance.resetApplicationScreenBrightness(),
    );
    VolumeController.instance.showSystemUI = true;
    _cancelControlsAutoHide();
    _sliderSeekThrottle?.cancel();
    _cancelDanmakuTicker();
    _gestureIndicatorTimer?.cancel();
    _progressSaveTimer?.cancel();
    for (final StreamSubscription<dynamic> subscription in _subscriptions) {
      subscription.cancel();
    }
    if (_isMagnet) {
      _coordinator.removeListener(_onStateChanged);
      _coordinator.reset();
    }
    if (_ownsPlayer) {
      widget.streamServer?.stop();
    }
    _onlineSourcesNotifier.dispose();
    _onlineSourceSearchingNotifier.dispose();
    if (_ownsPlayer) {
      _player.dispose();
    }
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
              onDoubleTap: showPlayer ? _handlePlayerDoubleTap : null,
              onVerticalDragStart: showPlayer ? _handleVerticalDragStart : null,
              onVerticalDragUpdate: showPlayer
                  ? _handleVerticalDragUpdate
                  : null,
              onVerticalDragEnd: showPlayer ? _handleVerticalDragEnd : null,
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
                  fontSize: _danmakuFontSize,
                  opacity: _danmakuOpacity,
                  speed: _danmakuSpeed,
                  showBackground: _danmakuShowBackground,
                  showStroke: _danmakuShowStroke,
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
          if (showPlayer && _gestureIndicatorText.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(child: _buildGestureIndicator()),
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
      onDoubleTap: _handlePlayerDoubleTap,
      onVerticalDragStart: _handleVerticalDragStart,
      onVerticalDragUpdate: _handleVerticalDragUpdate,
      onVerticalDragEnd: _handleVerticalDragEnd,
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
                          if (_hasOnlineContext) ...<Widget>[
                            _buildBottomAction(
                              icon: Icons.playlist_play_rounded,
                              label: '选集 (${_onlineEpisodes.length})',
                              onPressed: _showOnlineEpisodeSheet,
                            ),
                            _buildBottomAction(
                              icon: Icons.hub_rounded,
                              label: _isOnlineSourceSearching
                                  ? '找源中 (${_onlineSources.length})'
                                  : '换源 (${_onlineSources.length})',
                              onPressed: _showOnlineSourceSheet,
                            ),
                          ] else
                            _buildBottomAction(
                              icon: Icons.video_library_rounded,
                              label:
                                  '选集 (${DownloadManager().allTasks.length})',
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
                            icon: Icons.tune_rounded,
                            label: '弹幕样式',
                            onPressed: _showDanmakuStyleSheet,
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
                          value: _displayDuration.inMilliseconds <= 0
                              ? 0
                              : _effectivePosition.inMilliseconds
                                    .clamp(0, _displayDuration.inMilliseconds)
                                    .toDouble(),
                          min: 0,
                          max: _displayDuration.inMilliseconds <= 0
                              ? 1
                              : _displayDuration.inMilliseconds.toDouble(),
                          activeColor: Colors.blueAccent,
                          inactiveColor: Colors.white30,
                          onChangeStart: (_) => _cancelControlsAutoHide(),
                          onChanged: _seekFromSlider,
                          onChangeEnd: _finishSliderSeek,
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
                            _formatDuration(_displayDuration),
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

  Widget _buildGestureIndicator() {
    final double? progress = _gestureIndicatorProgress;
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: SizedBox(
            width: 132,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(_gestureIndicatorIcon, color: Colors.white, size: 34),
                const SizedBox(height: 10),
                Text(
                  _gestureIndicatorText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (progress != null) ...<Widget>[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      value: progress.clamp(0.0, 1.0).toDouble(),
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ],
              ],
            ),
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
    return prefix + source.sourceName;
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

class _OnlineSourceTierPill extends StatelessWidget {
  final String label;
  final Color color;

  const _OnlineSourceTierPill({required this.label, required this.color});

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

bool _isSameOnlineEpisode(
  OnlineEpisodeQuery? current,
  OnlineEpisodeQuery candidate,
) {
  if (current == null) {
    return false;
  }
  if (current.bangumiEpisodeId > 0 && candidate.bangumiEpisodeId > 0) {
    return current.bangumiEpisodeId == candidate.bangumiEpisodeId;
  }
  return current.episodeNumber > 0 &&
      current.episodeNumber == candidate.episodeNumber;
}

class _OnlineSourceSelectionSheet extends StatelessWidget {
  final ValueListenable<List<OnlineEpisodeSourceResult>> sourcesListenable;
  final ValueListenable<bool> searchingListenable;
  final String activeMediaUrl;
  final ValueChanged<OnlineEpisodeSourceResult> onSelected;

  const _OnlineSourceSelectionSheet({
    required this.sourcesListenable,
    required this.searchingListenable,
    required this.activeMediaUrl,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<OnlineEpisodeSourceResult>>(
      valueListenable: sourcesListenable,
      builder:
          (
            BuildContext context,
            List<OnlineEpisodeSourceResult> sources,
            Widget? child,
          ) {
            return ValueListenableBuilder<bool>(
              valueListenable: searchingListenable,
              builder: (BuildContext context, bool searching, Widget? child) {
                final List<MapEntry<String, List<OnlineEpisodeSourceResult>>>
                groups = _groupOnlineSources(sources).entries.toList()
                  ..sort((
                    MapEntry<String, List<OnlineEpisodeSourceResult>> a,
                    MapEntry<String, List<OnlineEpisodeSourceResult>> b,
                  ) {
                    final OnlineEpisodeSourceResult left = a.value.first;
                    final OnlineEpisodeSourceResult right = b.value.first;
                    if (left.verified != right.verified) {
                      return right.verified ? 1 : -1;
                    }
                    return right.score.compareTo(left.score);
                  });

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                  itemCount: groups.length + 1,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int index) {
                    if (index == 0) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const _PlayerPanelHeader(
                            icon: Icons.hub_rounded,
                            title: '在线换源',
                          ),
                          Text(
                            searching
                                ? '正在继续搜索，已解析 ${sources.length} 个可播源'
                                : '已解析 ${sources.length} 个可播源',
                            style: const TextStyle(color: Colors.grey),
                          ),
                          if (sources.isEmpty) ...<Widget>[
                            const SizedBox(height: 30),
                            Center(
                              child: searching
                                  ? const CircularProgressIndicator()
                                  : const Text(
                                      '暂无可切换的在线播放源。',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                            ),
                          ],
                        ],
                      );
                    }

                    final MapEntry<String, List<OnlineEpisodeSourceResult>>
                    group = groups[index - 1];
                    final String tier = _onlineSourceTierLabel(
                      group.value.first,
                    );
                    final Color tierColor = _onlineSourceTierColor(
                      Theme.of(context).colorScheme,
                      tier,
                    );
                    return Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                CircleAvatar(
                                  radius: 15,
                                  child: Text(
                                    group.key.trim().isEmpty
                                        ? '?'
                                        : group.key.trim().substring(0, 1),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    group.key,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                _OnlineSourceTierPill(
                                  label: tier,
                                  color: tierColor,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${group.value.length} 条线路',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List<Widget>.generate(
                                group.value.length,
                                (int sourceIndex) {
                                  final OnlineEpisodeSourceResult source =
                                      group.value[sourceIndex];
                                  final bool selected =
                                      source.mediaUrl == activeMediaUrl;
                                  return ChoiceChip(
                                    selected: selected,
                                    avatar: Icon(
                                      selected
                                          ? Icons.check_rounded
                                          : Icons.play_arrow_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      _onlineSourceLineLabel(
                                        source,
                                        sourceIndex,
                                      ),
                                    ),
                                    onSelected: (_) {
                                      Navigator.pop(context);
                                      onSelected(source);
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
    );
  }
}

class _OnlineEpisodeSelectionSheet extends StatelessWidget {
  final List<OnlineEpisodeQuery> episodes;
  final OnlineEpisodeQuery? activeQuery;
  final ValueChanged<OnlineEpisodeQuery> onSelected;

  const _OnlineEpisodeSelectionSheet({
    required this.episodes,
    required this.activeQuery,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final bool isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final String subjectTitle = episodes.isEmpty
        ? ''
        : episodes.first.subjectTitle;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, isLandscape ? 14 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _PlayerPanelHeader(
            icon: Icons.playlist_play_rounded,
            title: '在线选集',
          ),
          if (subjectTitle.trim().isNotEmpty)
            Text(
              subjectTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 4),
          const Text(
            '切换后会自动查找该集最优可播源并开始播放。',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double spacing = isLandscape ? 8 : 10;
                final int columns = constraints.maxWidth >= 520
                    ? 4
                    : (constraints.maxWidth >= 360 ? 3 : 2);
                final double itemWidth =
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;

                return SingleChildScrollView(
                  child: Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: episodes.map((OnlineEpisodeQuery episode) {
                      final bool selected = _isSameOnlineEpisode(
                        activeQuery,
                        episode,
                      );
                      return _OnlineEpisodeTile(
                        width: itemWidth,
                        episode: episode,
                        selected: selected,
                        onTap: selected
                            ? null
                            : () {
                                Navigator.pop(context);
                                onSelected(episode);
                              },
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OnlineEpisodeTile extends StatelessWidget {
  final double width;
  final OnlineEpisodeQuery episode;
  final bool selected;
  final VoidCallback? onTap;

  const _OnlineEpisodeTile({
    required this.width,
    required this.episode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String title = episode.episodeNumber > 0
        ? '第 ${episode.episodeNumber} 集'
        : '未命名';
    final String subtitle = episode.episodeTitle.trim();

    return SizedBox(
      width: width,
      child: Material(
        color: selected
            ? colors.primaryContainer
            : colors.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 82),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? colors.primary : colors.outlineVariant,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      selected
                          ? Icons.play_circle_fill_rounded
                          : Icons.play_circle_outline_rounded,
                      size: 18,
                      color: selected
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? colors.primary : colors.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  subtitle.isEmpty ? '点击播放' : subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? colors.onPrimaryContainer : Colors.grey,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ),
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
  final double fontSize;
  final double opacity;
  final double speed;
  final bool showBackground;
  final bool showStroke;
  final ValueChanged<int> onCompleted;

  const _DanmakuOverlay({
    required this.items,
    required this.fontSize,
    required this.opacity,
    required this.speed,
    required this.showBackground,
    required this.showStroke,
    required this.onCompleted,
  });

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
                  fontSize: fontSize,
                  opacity: opacity,
                  speed: speed,
                  showBackground: showBackground,
                  showStroke: showStroke,
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
  final double fontSize;
  final double opacity;
  final double speed;
  final bool showBackground;
  final bool showStroke;
  final VoidCallback onCompleted;

  const _DanmakuBullet({
    super.key,
    required this.item,
    required this.viewportSize,
    required this.fontSize,
    required this.opacity,
    required this.speed,
    required this.showBackground,
    required this.showStroke,
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

    final int baseDurationMs = widget.item.comment.mode == 1
        ? (7000 + widget.item.comment.text.length * 80).clamp(6500, 12000)
        : 4000;
    final int durationMs = (baseDurationMs / widget.speed).round().clamp(
      2600,
      18000,
    );
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
    return math.max(120.0, text.runes.length * widget.fontSize).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final double textWidth = _estimateTextWidth(widget.item.comment.text);
    final double laneHeight = widget.fontSize + 14;

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
          child: Opacity(
            opacity: (opacity * widget.opacity).clamp(0, 1),
            child: child,
          ),
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.showBackground
              ? Colors.black.withValues(alpha: 0.14)
              : Colors.transparent,
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
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w600,
              shadows: widget.showStroke
                  ? const <Shadow>[
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 3,
                        offset: Offset(0.8, 0.8),
                      ),
                    ]
                  : const <Shadow>[],
            ),
          ),
        ),
      ),
    );
  }
}

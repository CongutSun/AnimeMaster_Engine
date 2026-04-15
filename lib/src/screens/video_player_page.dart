import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../coordinator/episode_coordinator.dart';
import '../models/playable_media.dart';

class VideoPlayerPage extends StatefulWidget {
  final PlayableMedia media;

  const VideoPlayerPage({super.key, required this.media});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  final EpisodeCoordinator _coordinator = EpisodeCoordinator();
  late final bool _isMagnet;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _isMagnet = widget.media.url.toLowerCase().startsWith('magnet:');

    if (_isMagnet) {
      _coordinator.addListener(_onStateChanged);
      _coordinator.loadEpisode(widget.media.url);
    } else {
      _openMedia(widget.media);
    }
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

  void _openMedia(PlayableMedia media) {
    _player.open(Media(media.url, httpHeaders: media.headers));
  }

  @override
  void dispose() {
    if (_isMagnet) {
      _coordinator.removeListener(_onStateChanged);
      _coordinator.reset();
    }
    _player.dispose();
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
          if (showPlayer)
            Center(
              child: Video(
                controller: _controller,
                controls: AdaptiveVideoControls,
              ),
            ),
          if (!showPlayer) _buildStateOverlay(),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    widget.media.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateOverlay() {
    String message = '';
    bool isError = false;

    switch (_coordinator.currentState) {
      case PlaybackState.idle:
      case PlaybackState.fetching:
        message = '正在获取种子元数据...';
        break;
      case PlaybackState.resolving:
        message = '正在解析文件树并准备播放...';
        break;
      case PlaybackState.error:
        message = '播放失败：${_coordinator.errorMessage}';
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
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
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

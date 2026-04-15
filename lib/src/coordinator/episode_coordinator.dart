import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/playable_media.dart';
import 'torrent_media_resolver.dart';
import '../utils/torrent_stream_server.dart';

enum PlaybackState {
  idle,           
  fetching,       
  resolving,      
  readyToPlay,    
  error           
}

class EpisodeCoordinator extends ChangeNotifier {
  static final EpisodeCoordinator _instance = EpisodeCoordinator._internal();
  factory EpisodeCoordinator() => _instance;
  EpisodeCoordinator._internal();

  bool _isBusy = false;
  
  PlaybackState _currentState = PlaybackState.idle;
  PlaybackState get currentState => _currentState;
  
  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  PlayableMedia? _currentMedia;
  PlayableMedia? get currentMedia => _currentMedia;

  TorrentStreamServer? _streamServer;

  Future<void> loadEpisode(String magnetUrl) async {
    if (_isBusy) return;
    _isBusy = true;

    try {
      _updateState(PlaybackState.fetching);

      final resolver = TorrentMediaResolver();
      _updateState(PlaybackState.resolving);
      
      // 解析种子并启动下载任务
      final mediaInfo = await resolver.resolveAndPrepare(magnetUrl);
      
      // 清理历史流媒体服务器实例
      _streamServer?.stop();
      
      // 实例化本地流媒体服务器，用于边下边播
      _streamServer = TorrentStreamServer(
        videoFilePath: mediaInfo.filePath,
        videoSize: mediaInfo.fileSize,
        infoHash: mediaInfo.infoHash,
      );

      // 启动服务器并获取动态生成的播放地址
      final streamUrl = await _streamServer!.start();
      
      _currentMedia = PlayableMedia(
        title: mediaInfo.title,
        url: streamUrl,
      );
      
      _updateState(PlaybackState.readyToPlay);
    } catch (e) {
      _errorMessage = e.toString();
      _updateState(PlaybackState.error);
      debugPrint('Playback State Machine Error: $_errorMessage');
    } finally {
      _isBusy = false;
    }
  }

  void reset() {
    _streamServer?.stop();
    _streamServer = null;
    _currentMedia = null;
    _isBusy = false;
    _updateState(PlaybackState.idle);
  }

  void _updateState(PlaybackState state) {
    _currentState = state;
    notifyListeners();
  }
}
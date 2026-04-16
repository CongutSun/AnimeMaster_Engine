import 'package:flutter/foundation.dart';

import '../managers/download_manager.dart';
import '../models/playable_media.dart';
import '../utils/torrent_stream_server.dart';
import 'torrent_media_resolver.dart';

enum PlaybackState { idle, fetching, resolving, readyToPlay, error }

class EpisodeCoordinator extends ChangeNotifier {
  static final EpisodeCoordinator _instance = EpisodeCoordinator._internal();
  factory EpisodeCoordinator() => _instance;
  EpisodeCoordinator._internal();

  bool _isBusy = false;
  PlaybackState _currentState = PlaybackState.idle;
  String _errorMessage = '';
  PlayableMedia? _currentMedia;
  List<ResolvedMediaInfo> _mediaItems = <ResolvedMediaInfo>[];
  int _currentIndex = 0;
  TorrentStreamServer? _streamServer;
  String _subjectTitle = '';
  String _episodeHint = '';

  PlaybackState get currentState => _currentState;
  String get errorMessage => _errorMessage;
  PlayableMedia? get currentMedia => _currentMedia;
  List<ResolvedMediaInfo> get mediaItems =>
      List<ResolvedMediaInfo>.unmodifiable(_mediaItems);
  int get currentIndex => _currentIndex;
  bool get hasMultipleEpisodes => _mediaItems.length > 1;

  Future<void> loadEpisode(
    String rawSource, {
    String preferredTitle = '',
    String subjectTitle = '',
    String episodeLabel = '',
  }) async {
    if (_isBusy) {
      return;
    }

    _isBusy = true;
    _errorMessage = '';
    _subjectTitle = subjectTitle.trim();
    _episodeHint = episodeLabel.trim();

    try {
      _updateState(PlaybackState.fetching);

      final TorrentMediaResolver resolver = TorrentMediaResolver();
      _updateState(PlaybackState.resolving);

      final PreparedTorrentTask preparedTask = await resolver.prepareTask(
        rawSource,
        preferredTitle: preferredTitle,
        subjectTitle: subjectTitle,
        episodeLabel: episodeLabel,
      );

      await DownloadManager().addTask(
        preparedTask.taskInfo,
        preparedTask.torrentBytes,
      );

      _mediaItems = preparedTask.mediaItems;
      _currentIndex = preparedTask.initialIndex;
      await _openMediaAt(_currentIndex);
    } catch (error) {
      _errorMessage = error.toString();
      _updateState(PlaybackState.error);
      debugPrint('Playback State Machine Error: $_errorMessage');
    } finally {
      _isBusy = false;
    }
  }

  Future<void> selectEpisode(int index) async {
    if (_isBusy || index < 0 || index >= _mediaItems.length) {
      return;
    }
    if (index == _currentIndex && _currentMedia != null) {
      return;
    }

    _isBusy = true;
    _errorMessage = '';

    try {
      _updateState(PlaybackState.resolving);
      _currentIndex = index;
      await _openMediaAt(index);
    } catch (error) {
      _errorMessage = error.toString();
      _updateState(PlaybackState.error);
      debugPrint('Episode switch failed: $_errorMessage');
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _openMediaAt(int index) async {
    final ResolvedMediaInfo mediaInfo = _mediaItems[index];

    _streamServer?.stop();
    _streamServer = TorrentStreamServer(
      videoFilePath: mediaInfo.filePath,
      videoSize: mediaInfo.fileSize,
      infoHash: mediaInfo.infoHash,
    );

    final String streamUrl = await _streamServer!.start();
    _currentMedia = PlayableMedia(
      title: mediaInfo.title,
      url: streamUrl,
      localFilePath: mediaInfo.filePath,
      subjectTitle: _subjectTitle.isNotEmpty ? _subjectTitle : mediaInfo.title,
      episodeLabel: mediaInfo.episodeLabel.isNotEmpty
          ? mediaInfo.episodeLabel
          : _episodeHint,
    );

    _updateState(PlaybackState.readyToPlay);
  }

  void reset() {
    _streamServer?.stop();
    _streamServer = null;
    _currentMedia = null;
    _mediaItems = <ResolvedMediaInfo>[];
    _currentIndex = 0;
    _errorMessage = '';
    _isBusy = false;
    _subjectTitle = '';
    _episodeHint = '';
    _updateState(PlaybackState.idle);
  }

  void _updateState(PlaybackState state) {
    _currentState = state;
    notifyListeners();
  }
}

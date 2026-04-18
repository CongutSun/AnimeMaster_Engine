import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:dtorrent_task/dtorrent_task.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_task_info.dart';
import '../services/background_download_service.dart';
import '../utils/tracker_pool.dart';

class DownloadManager extends ChangeNotifier {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;

  static const int _maxActiveDownloads = 2;
  static const int _maxActiveSeedsWhenIdle = 1;

  final Map<String, TorrentTask> _activeTasks = {};
  final Map<String, DownloadTaskInfo> _taskConfigs = {};
  final Map<String, bool> _pausedStates = {};
  final Map<String, bool> _queuedStates = {};
  final Map<String, int> _lastDownloadedBytes = {};
  final Map<String, double> _currentSpeeds = {};
  final Map<String, double> _currentUploadSpeeds = {};
  final Map<String, Timer> _peerWarmupTimers = {};
  final Set<String> _streamOptimizedTasks = <String>{};
  String? _playbackPriorityHash;
  bool _isScheduling = false;
  Timer? _speedTimer;

  DownloadManager._internal() {
    _speedTimer = Timer.periodic(const Duration(seconds: 2), _calculateSpeeds);
  }

  List<DownloadTaskInfo> get allTasks => _taskConfigs.values.toList();
  bool hasTask(String hash) => _activeTasks.containsKey(hash);

  Future<void> initPersistedTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final tasksJson = prefs.getString('anime_saved_tasks');
    bool hasMigratedTask = false;

    if (tasksJson != null) {
      final List<dynamic> decodedList = jsonDecode(tasksJson);
      for (var item in decodedList) {
        DownloadTaskInfo info = DownloadTaskInfo.fromJson(item);
        final torrentFile = File('${info.savePath}/meta.torrent');
        if (await torrentFile.exists()) {
          try {
            final bytes = await torrentFile.readAsBytes();
            final torrent = await Torrent.parseFromBytes(bytes);

            if (info.targetPath.isEmpty) {
              info = info.copyWith(
                targetPath: _resolveTargetPath(info.savePath, torrent),
              );
              hasMigratedTask = true;
            }
            if (info.targetSize <= 0 && info.targetPath.isNotEmpty) {
              info = info.copyWith(
                targetSize: _resolveTargetSize(torrent, info.targetPath),
              );
              hasMigratedTask = true;
            }

            _injectTrackersToTorrent(torrent, info.url);

            final task = TorrentTask.newTask(torrent, info.savePath);
            _activeTasks[info.hash] = task;
            _taskConfigs[info.hash] = info;
            _pausedStates[info.hash] = info.isPaused;
            _queuedStates[info.hash] = false;
            _lastDownloadedBytes[info.hash] = 0;
            _currentSpeeds[info.hash] = 0.0;
            _currentUploadSpeeds[info.hash] = 0.0;
          } catch (e) {
            debugPrint('Failed to restore task: $e');
          }
        }
      }
      if (hasMigratedTask) {
        await _saveTasksToPrefs();
      }
      await _enforceConcurrency();
      _syncBackgroundService();
      notifyListeners();
    }
  }

  Future<void> _saveTasksToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final tasksList = _taskConfigs.values.map((e) => e.toJson()).toList();
    await prefs.setString('anime_saved_tasks', jsonEncode(tasksList));
  }

  void _calculateSpeeds(Timer timer) {
    bool shouldNotify = false;
    for (var entry in _activeTasks.entries) {
      final hash = entry.key;
      final task = entry.value;
      final config = _taskConfigs[hash];

      final bool isPaused =
          _pausedStates[hash] == true || _queuedStates[hash] == true;

      // 1. 完成后保持任务运行，进入做种状态。
      if (config != null && !config.isCompleted && task.progress >= 1.0) {
        config.isCompleted = true;
        config.isPaused = false;
        _pausedStates[hash] = false;
        _queuedStates[hash] = false;
        _peerWarmupTimers.remove(hash)?.cancel();
        _currentSpeeds[hash] = 0.0;
        _currentUploadSpeeds[hash] = _uploadSpeedInKb(task);
        unawaited(_saveTasksToPrefs());
        unawaited(_enforceConcurrency());
        shouldNotify = true;
        continue;
      }

      // 2. 暂停任务速度归零；已完成但未暂停的任务显示上传速度。
      if (isPaused) {
        _currentSpeeds[hash] = 0.0;
        _currentUploadSpeeds[hash] = 0.0;
        continue;
      }

      if (config?.isCompleted == true) {
        _currentSpeeds[hash] = 0.0;
        _currentUploadSpeeds[hash] = _uploadSpeedInKb(task);
        shouldNotify = true;
        continue;
      }

      // 3. 常规速度计算
      int currentBytes = task.downloaded ?? 0;
      int lastBytes = _lastDownloadedBytes[hash] ?? 0;
      final double deltaSpeed = (currentBytes - lastBytes) / 1024.0;
      final double peerSpeed = (task.currentDownloadSpeed * 1000) / 1024.0;
      final double speed = peerSpeed > deltaSpeed ? peerSpeed : deltaSpeed;
      _currentSpeeds[hash] = speed > 0 ? speed : 0.0;
      _currentUploadSpeeds[hash] = _uploadSpeedInKb(task);
      _lastDownloadedBytes[hash] = currentBytes;
      shouldNotify = true;
    }
    if (shouldNotify) notifyListeners();
  }

  Future<void> addTask(
    DownloadTaskInfo info,
    Uint8List torrentBytes, {
    bool streamOptimized = false,
  }) async {
    if (_activeTasks.containsKey(info.hash)) {
      final existingConfig = _taskConfigs[info.hash];
      if (existingConfig != null) {
        if (streamOptimized) {
          _streamOptimizedTasks.add(info.hash);
        }
        _taskConfigs[info.hash] = existingConfig.copyWith(
          title: _preferRicherText(existingConfig.title, info.title),
          url: info.url,
          savePath: info.savePath,
          targetPath: info.targetPath,
          targetSize: info.targetSize,
          subjectTitle: _preferRicherText(
            existingConfig.subjectTitle,
            info.subjectTitle,
          ),
          episodeLabel: _preferRicherText(
            existingConfig.episodeLabel,
            info.episodeLabel,
          ),
          bangumiSubjectId: existingConfig.bangumiSubjectId > 0
              ? existingConfig.bangumiSubjectId
              : info.bangumiSubjectId,
          bangumiEpisodeId: existingConfig.bangumiEpisodeId > 0
              ? existingConfig.bangumiEpisodeId
              : info.bangumiEpisodeId,
        );
        _taskConfigs[info.hash]!.isPaused = false;
        await _startOrResumeTask(info.hash, preferred: streamOptimized);
        await _saveTasksToPrefs();
        notifyListeners();
      }
      return;
    }

    final targetDir = Directory(info.savePath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final torrentFile = File('${info.savePath}/meta.torrent');
    if (!await torrentFile.exists()) {
      await torrentFile.writeAsBytes(torrentBytes);
    }

    final torrent = await Torrent.parseFromBytes(torrentBytes);

    _injectTrackersToTorrent(torrent, info.url);

    if (streamOptimized) {
      _streamOptimizedTasks.add(info.hash);
    }

    final task = TorrentTask.newTask(torrent, info.savePath, streamOptimized);

    _activeTasks[info.hash] = task;
    _taskConfigs[info.hash] = info;
    info.isPaused = false;
    _pausedStates[info.hash] = false;
    _queuedStates[info.hash] = false;
    _lastDownloadedBytes[info.hash] = 0;
    _currentSpeeds[info.hash] = 0.0;
    _currentUploadSpeeds[info.hash] = 0.0;

    await _startOrResumeTask(info.hash, preferred: streamOptimized);
    await _saveTasksToPrefs();
    _syncBackgroundService();
    notifyListeners();
  }

  Future<void> _startOrResumeTask(
    String hash, {
    bool preferred = false,
    bool enforceSchedule = true,
  }) async {
    final DownloadTaskInfo? config = _taskConfigs[hash];
    TorrentTask? task = _activeTasks[hash];
    if (task == null || config == null) {
      return;
    }

    if (task.state == TaskState.paused) {
      task.resume();
    } else if (task.state == TaskState.running) {
      // Already running.
    } else {
      _injectTrackersToTorrent(task.metaInfo, config.url);
      task = TorrentTask.newTask(
        task.metaInfo,
        config.savePath,
        _streamOptimizedTasks.contains(hash),
      );
      _activeTasks[hash] = task;
      await task.start();
    }

    _addDhtBootstrapNodes(task);
    _pausedStates[hash] = false;
    config.isPaused = false;
    _queuedStates[hash] = false;
    _lastDownloadedBytes[hash] = task.downloaded ?? 0;
    if (!config.isCompleted) {
      _boostPeerDiscovery(hash);
    }
    if (enforceSchedule) {
      await _enforceConcurrency(preferredHash: preferred ? hash : null);
    } else {
      _syncBackgroundService();
    }
  }

  Future<void> prepareForPlayback(String hash) async {
    if (!_activeTasks.containsKey(hash)) {
      return;
    }
    _playbackPriorityHash = hash;
    _streamOptimizedTasks.add(hash);
    _pausedStates[hash] = false;
    _taskConfigs[hash]?.isPaused = false;
    _queuedStates[hash] = false;
    await _startOrResumeTask(hash, preferred: true);
    await _saveTasksToPrefs();
  }

  void prioritizePlaybackRange(
    String hash,
    String absolutePath,
    int filePosition,
    int length,
  ) {
    final TorrentTask? task = _activeTasks[hash];
    final DownloadTaskInfo? config = _taskConfigs[hash];
    if (task == null || config == null || config.isCompleted) {
      return;
    }

    _playbackPriorityHash = hash;
    _streamOptimizedTasks.add(hash);

    final TorrentFile? torrentFile = _findTorrentFileForPath(
      task.metaInfo,
      absolutePath,
    );
    final int safeLength = math.max(length, 256 * 1024);
    final int offsetStart =
        (torrentFile?.offset ?? 0) + math.max(0, filePosition);
    final int offsetEnd = offsetStart + safeLength;
    final int startPiece = offsetStart ~/ task.metaInfo.pieceLength;
    final int endPiece = math.min(
      task.metaInfo.pieces.length - 1,
      (offsetEnd ~/ task.metaInfo.pieceLength) + 6,
    );
    if (startPiece > endPiece) {
      return;
    }

    try {
      task.pieceManager?.pieceSelector.setPriorityPieces(<int>{
        for (int i = startPiece; i <= endPiece; i++) i,
      });
      if (task.connectedPeersNumber < 4) {
        _requestPeerSources(task, trackerLimit: 4);
      }
    } catch (_) {}
  }

  Future<bool> isRangeReadable(
    String hash,
    String path, {
    int start = 0,
    int bytes = 512 * 1024,
  }) async {
    if (!hasTask(hash)) {
      return false;
    }
    final File file = File(path);
    if (!await file.exists()) {
      return false;
    }
    final int requiredBytes = math.max(1, bytes);
    final int probeLength = math.min(requiredBytes, 64 * 1024);
    try {
      if (await file.length() < start + probeLength) {
        return false;
      }
      final RandomAccessFile raf = await file.open(mode: FileMode.read);
      try {
        await raf.setPosition(start);
        final List<int> probe = await raf.read(probeLength);
        return probe.isNotEmpty && !_isZeroFilled(probe);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> _enforceConcurrency({String? preferredHash}) async {
    if (_isScheduling) {
      return;
    }

    _isScheduling = true;
    try {
      if (preferredHash != null) {
        _playbackPriorityHash = preferredHash;
      }

      final List<String> downloadCandidates = _taskConfigs.entries
          .where(
            (MapEntry<String, DownloadTaskInfo> entry) =>
                !entry.value.isCompleted && _pausedStates[entry.key] != true,
          )
          .map((MapEntry<String, DownloadTaskInfo> entry) => entry.key)
          .toList();
      downloadCandidates.sort(_compareTransferPriority);

      final Set<String> allowedDownloads = downloadCandidates
          .take(_maxActiveDownloads)
          .toSet();

      final List<String> seedCandidates = _taskConfigs.entries
          .where(
            (MapEntry<String, DownloadTaskInfo> entry) =>
                entry.value.isCompleted && _pausedStates[entry.key] != true,
          )
          .map((MapEntry<String, DownloadTaskInfo> entry) => entry.key)
          .toList();
      seedCandidates.sort(_compareTransferPriority);

      final int seedSlots = allowedDownloads.isEmpty
          ? _maxActiveSeedsWhenIdle
          : 0;
      final Set<String> allowedSeeds = seedCandidates.take(seedSlots).toSet();
      final Set<String> allowed = <String>{
        ...allowedDownloads,
        ...allowedSeeds,
      };

      for (final MapEntry<String, TorrentTask> entry in _activeTasks.entries) {
        final String hash = entry.key;
        final TorrentTask task = entry.value;
        final DownloadTaskInfo? config = _taskConfigs[hash];
        if (config == null) {
          continue;
        }

        if (_pausedStates[hash] == true) {
          _queuedStates[hash] = false;
          continue;
        }

        if (allowed.contains(hash)) {
          _queuedStates[hash] = false;
          if (task.state == TaskState.paused ||
              task.state == TaskState.stopped) {
            await _startOrResumeTask(hash, enforceSchedule: false);
          }
        } else {
          _queuedStates[hash] = true;
          _peerWarmupTimers.remove(hash)?.cancel();
          _currentSpeeds[hash] = 0.0;
          _currentUploadSpeeds[hash] = 0.0;
          if (task.state == TaskState.running) {
            task.pause();
          }
        }
      }

      _syncBackgroundService();
    } finally {
      _isScheduling = false;
    }
  }

  int _compareTransferPriority(String a, String b) {
    final String? priorityHash = _playbackPriorityHash;
    if (a == priorityHash && b != priorityHash) {
      return -1;
    }
    if (b == priorityHash && a != priorityHash) {
      return 1;
    }

    final bool aQueued = _queuedStates[a] == true;
    final bool bQueued = _queuedStates[b] == true;
    if (aQueued != bQueued) {
      return aQueued ? 1 : -1;
    }

    return 0;
  }

  TorrentFile? _findTorrentFileForPath(Torrent torrent, String absolutePath) {
    final String normalizedTarget = _normalizePath(absolutePath);
    for (final TorrentFile file in torrent.files) {
      final String normalizedRelative = _normalizePath(file.path);
      if (normalizedTarget.endsWith(normalizedRelative)) {
        return file;
      }
    }
    for (final TorrentFile file in torrent.files) {
      final String normalizedName = _normalizePath(file.name);
      if (normalizedTarget.endsWith(normalizedName)) {
        return file;
      }
    }
    return null;
  }

  String _normalizePath(String path) {
    return path.replaceAll('\\', '/').toLowerCase();
  }

  bool _isZeroFilled(List<int> buffer) {
    if (buffer.isEmpty || buffer.first != 0 || buffer.last != 0) {
      return false;
    }
    return !buffer.any((int byte) => byte != 0);
  }

  void _addDhtBootstrapNodes(TorrentTask task) {
    for (final Uri node in TrackerPool.dhtBootstrapNodes) {
      try {
        task.addDHTNode(node);
      } catch (_) {}
    }
  }

  void _boostPeerDiscovery(String hash) {
    _peerWarmupTimers[hash]?.cancel();
    final TorrentTask? task = _activeTasks[hash];
    final DownloadTaskInfo? config = _taskConfigs[hash];
    if (task == null || config == null || config.isCompleted) {
      return;
    }

    _requestPeerSources(task, trackerLimit: 8);

    int ticks = 0;
    _peerWarmupTimers[hash] = Timer.periodic(const Duration(seconds: 15), (
      Timer timer,
    ) {
      final TorrentTask? activeTask = _activeTasks[hash];
      final DownloadTaskInfo? activeConfig = _taskConfigs[hash];
      if (activeTask == null ||
          activeConfig == null ||
          activeConfig.isCompleted ||
          _pausedStates[hash] == true ||
          _queuedStates[hash] == true) {
        timer.cancel();
        _peerWarmupTimers.remove(hash);
        return;
      }

      ticks++;
      final bool needsMorePeers =
          activeTask.connectedPeersNumber < 8 || getSpeed(hash) < 64;
      if (needsMorePeers) {
        _requestPeerSources(activeTask, trackerLimit: ticks <= 2 ? 8 : 4);
      } else {
        activeTask.requestPeersFromDHT();
      }

      if (ticks >= 8 || activeTask.connectedPeersNumber >= 24) {
        timer.cancel();
        _peerWarmupTimers.remove(hash);
      }
    });
  }

  void _requestPeerSources(TorrentTask task, {required int trackerLimit}) {
    task.requestPeersFromDHT();

    int announced = 0;
    for (final String tracker in TrackerPool.robustTrackers) {
      if (announced >= trackerLimit) {
        break;
      }
      try {
        task.startAnnounceUrl(Uri.parse(tracker), task.metaInfo.infoHashBuffer);
        announced++;
      } catch (_) {}
    }
  }

  void _injectTrackersToTorrent(Torrent torrent, String magnetUrl) {
    final Set<String> existingTrackers = torrent.announces
        .map((e) => e.toString())
        .toSet();

    final List<String> highSpeedTrackers = TrackerPool.robustTrackers;

    for (String tracker in highSpeedTrackers) {
      if (!existingTrackers.contains(tracker)) {
        try {
          torrent.announces.add(Uri.parse(tracker));
          existingTrackers.add(tracker);
        } catch (_) {}
      }
    }

    final trRegex = RegExp(r'&tr=([^&]+)');
    final matches = trRegex.allMatches(magnetUrl);
    for (var match in matches) {
      final tr = Uri.decodeComponent(match.group(1)!);
      if (!existingTrackers.contains(tr)) {
        try {
          torrent.announces.add(Uri.parse(tr));
        } catch (_) {}
      }
    }
  }

  String _resolveTargetPath(String savePath, Torrent torrent) {
    const List<String> videoExtensions = <String>[
      '.mp4',
      '.mkv',
      '.avi',
      '.flv',
      '.rmvb',
      '.ts',
      '.m2ts',
      '.wmv',
      '.webm',
    ];

    if (torrent.files.isEmpty) {
      return '';
    }

    var targetFile = torrent.files.first;
    int maxSize = -1;

    for (final file in torrent.files) {
      final String lowerName = file.name.toLowerCase();
      final bool isVideo = videoExtensions.any(lowerName.endsWith);
      if (isVideo && file.length > maxSize) {
        maxSize = file.length;
        targetFile = file;
      }
    }

    if (maxSize < 0) {
      for (final file in torrent.files) {
        if (file.length > maxSize) {
          maxSize = file.length;
          targetFile = file;
        }
      }
    }

    final String relativePath = targetFile.path.replaceAll(
      '/',
      Platform.pathSeparator,
    );
    return '$savePath${Platform.pathSeparator}$relativePath';
  }

  int _resolveTargetSize(Torrent torrent, String targetPath) {
    final TorrentFile? file = _findTorrentFileForPath(torrent, targetPath);
    return file?.length ?? 0;
  }

  String _preferRicherText(String currentValue, String incomingValue) {
    final String current = currentValue.trim();
    final String incoming = incomingValue.trim();

    if (incoming.isEmpty) {
      return currentValue;
    }
    if (current.isEmpty) {
      return incomingValue;
    }
    if (incoming.length > current.length) {
      return incomingValue;
    }
    return currentValue;
  }

  // 状态获取：一旦持久化状态为已完成，直接返回 1.0，不再依赖引擎校验
  double getProgress(String hash) {
    if (_taskConfigs[hash]?.isCompleted == true) return 1.0;
    return _activeTasks[hash]?.progress ?? 0.0;
  }

  double getSpeed(String hash) => _currentSpeeds[hash] ?? 0.0;
  double getUploadSpeed(String hash) => _currentUploadSpeeds[hash] ?? 0.0;
  bool isPaused(String hash) => _pausedStates[hash] ?? false;
  bool isQueued(String hash) => _queuedStates[hash] ?? false;
  bool isSeeding(String hash) {
    final DownloadTaskInfo? config = _taskConfigs[hash];
    final TorrentTask? task = _activeTasks[hash];
    return config?.isCompleted == true &&
        _pausedStates[hash] != true &&
        _queuedStates[hash] != true &&
        task?.state == TaskState.running;
  }

  Future<void> toggleTask(String hash) async {
    final task = _activeTasks[hash];
    final config = _taskConfigs[hash];
    if (task == null || config == null) return;

    if (isPaused(hash) || isQueued(hash) || task.state != TaskState.running) {
      _pausedStates[hash] = false;
      config.isPaused = false;
      _queuedStates[hash] = false;
      await _startOrResumeTask(hash, preferred: true);
    } else {
      task.pause();
      _pausedStates[hash] = true;
      config.isPaused = true;
      _queuedStates[hash] = false;
      _peerWarmupTimers.remove(hash)?.cancel();
      _currentSpeeds[hash] = 0.0;
      _currentUploadSpeeds[hash] = 0.0;
      await _enforceConcurrency();
    }
    await _saveTasksToPrefs();
    _syncBackgroundService();
    notifyListeners();
  }

  Future<void> deleteTask(String hash) async {
    final task = _activeTasks[hash];
    final config = _taskConfigs[hash];

    task?.stop();
    _peerWarmupTimers.remove(hash)?.cancel();
    _activeTasks.remove(hash);
    _taskConfigs.remove(hash);
    _pausedStates.remove(hash);
    _queuedStates.remove(hash);
    _streamOptimizedTasks.remove(hash);
    if (_playbackPriorityHash == hash) {
      _playbackPriorityHash = null;
    }
    _currentSpeeds.remove(hash);
    _currentUploadSpeeds.remove(hash);
    _lastDownloadedBytes.remove(hash);

    if (config != null) {
      try {
        final dir = Directory(config.savePath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}
    }

    await _saveTasksToPrefs();
    await _enforceConcurrency();
    _syncBackgroundService();
    notifyListeners();
  }

  double _uploadSpeedInKb(TorrentTask task) {
    final double peerUploadSpeed = (task.uploadSpeed * 1000) / 1024.0;
    return peerUploadSpeed > 0 ? peerUploadSpeed : 0.0;
  }

  void _syncBackgroundService() {
    final bool hasActiveTransfer = _activeTasks.keys.any((String hash) {
      final DownloadTaskInfo? config = _taskConfigs[hash];
      final TorrentTask? task = _activeTasks[hash];
      if (config == null ||
          task == null ||
          _pausedStates[hash] == true ||
          _queuedStates[hash] == true) {
        return false;
      }
      return task.state == TaskState.running;
    });

    unawaited(BackgroundDownloadService.setActive(hasActiveTransfer));
  }

  @override
  void dispose() {
    _speedTimer?.cancel();
    for (final Timer timer in _peerWarmupTimers.values) {
      timer.cancel();
    }
    _peerWarmupTimers.clear();
    for (var task in _activeTasks.values) {
      task.stop();
    }
    unawaited(BackgroundDownloadService.setActive(false));
    super.dispose();
  }
}

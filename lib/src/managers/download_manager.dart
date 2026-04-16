import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dtorrent_task/dtorrent_task.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_task_info.dart';
import '../utils/tracker_pool.dart';

class DownloadManager extends ChangeNotifier {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;

  final Map<String, TorrentTask> _activeTasks = {};
  final Map<String, DownloadTaskInfo> _taskConfigs = {};
  final Map<String, bool> _pausedStates = {};
  final Map<String, int> _lastDownloadedBytes = {};
  final Map<String, double> _currentSpeeds = {};
  final Map<String, Timer> _peerWarmupTimers = {};
  Timer? _speedTimer;

  DownloadManager._internal() {
    _speedTimer = Timer.periodic(const Duration(seconds: 1), _calculateSpeeds);
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

            _injectTrackersToTorrent(torrent, info.url);

            final task = TorrentTask.newTask(torrent, info.savePath);
            _activeTasks[info.hash] = task;
            _taskConfigs[info.hash] = info;
            _pausedStates[info.hash] = true; // 重启后默认均为暂停状态
            _lastDownloadedBytes[info.hash] = 0;
            _currentSpeeds[info.hash] = 0.0;
          } catch (e) {
            debugPrint('Failed to restore task: $e');
          }
        }
      }
      if (hasMigratedTask) {
        await _saveTasksToPrefs();
      }
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

      // 1. 状态拦截：如果任务刚达到 100% 且标记未完成
      if (config != null && !config.isCompleted && task.progress >= 1.0) {
        config.isCompleted = true;
        _pausedStates[hash] = true;
        _peerWarmupTimers.remove(hash)?.cancel();
        task.stop();
        _currentSpeeds[hash] = 0.0;
        _saveTasksToPrefs();
        shouldNotify = true;
        continue;
      }

      // 2. 暂停或已完成的任务，速度归零
      if (_pausedStates[hash] == true || config?.isCompleted == true) {
        _currentSpeeds[hash] = 0.0;
        continue;
      }

      // 3. 常规速度计算
      int currentBytes = task.downloaded ?? 0;
      int lastBytes = _lastDownloadedBytes[hash] ?? 0;
      final double deltaSpeed = (currentBytes - lastBytes) / 1024.0;
      final double peerSpeed = (task.currentDownloadSpeed * 1000) / 1024.0;
      final double speed = peerSpeed > deltaSpeed ? peerSpeed : deltaSpeed;
      _currentSpeeds[hash] = speed > 0 ? speed : 0.0;
      _lastDownloadedBytes[hash] = currentBytes;
      shouldNotify = true;
    }
    if (shouldNotify) notifyListeners();
  }

  Future<void> addTask(DownloadTaskInfo info, Uint8List torrentBytes) async {
    if (_activeTasks.containsKey(info.hash)) {
      final existingConfig = _taskConfigs[info.hash];
      if (existingConfig != null) {
        _taskConfigs[info.hash] = existingConfig.copyWith(
          title: _preferRicherText(existingConfig.title, info.title),
          url: info.url,
          savePath: info.savePath,
          targetPath: info.targetPath,
          subjectTitle: _preferRicherText(
            existingConfig.subjectTitle,
            info.subjectTitle,
          ),
          episodeLabel: _preferRicherText(
            existingConfig.episodeLabel,
            info.episodeLabel,
          ),
        );
        await _startOrResumeTask(info.hash);
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

    final task = TorrentTask.newTask(torrent, info.savePath);

    _activeTasks[info.hash] = task;
    _taskConfigs[info.hash] = info;
    _pausedStates[info.hash] = false;
    _lastDownloadedBytes[info.hash] = 0;
    _currentSpeeds[info.hash] = 0.0;

    await _startOrResumeTask(info.hash);
    await _saveTasksToPrefs();
    notifyListeners();
  }

  Future<void> _startOrResumeTask(String hash) async {
    final DownloadTaskInfo? config = _taskConfigs[hash];
    TorrentTask? task = _activeTasks[hash];
    if (task == null || config == null || config.isCompleted) {
      return;
    }

    if (task.state == TaskState.paused) {
      task.resume();
    } else if (task.state == TaskState.running) {
      // Already running.
    } else {
      _injectTrackersToTorrent(task.metaInfo, config.url);
      task = TorrentTask.newTask(task.metaInfo, config.savePath);
      _activeTasks[hash] = task;
      await task.start();
    }

    _addDhtBootstrapNodes(task);
    _pausedStates[hash] = false;
    _lastDownloadedBytes[hash] = task.downloaded ?? 0;
    _boostPeerDiscovery(hash);
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
          _pausedStates[hash] == true) {
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
  bool isPaused(String hash) => _pausedStates[hash] ?? false;

  Future<void> toggleTask(String hash) async {
    final task = _activeTasks[hash];
    final config = _taskConfigs[hash];
    if (task == null || config == null) return;

    // 已完成的任务禁止再次启动
    if (config.isCompleted) return;

    if (isPaused(hash)) {
      await _startOrResumeTask(hash);
    } else {
      task.pause();
      _pausedStates[hash] = true;
      _peerWarmupTimers.remove(hash)?.cancel();
      _currentSpeeds[hash] = 0.0;
    }
    await _saveTasksToPrefs();
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
    _currentSpeeds.remove(hash);
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
    notifyListeners();
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
    super.dispose();
  }
}

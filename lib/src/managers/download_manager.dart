import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task/dtorrent_task.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_task_info.dart';
import '../repositories/download_task_repository.dart';
import '../services/background_download_service.dart';
import '../utils/tracker_pool.dart';

List<DownloadTaskInfo> _decodeLegacyDownloadTasks(String tasksJson) {
  final Object? decoded = jsonDecode(tasksJson);
  if (decoded is! List) {
    return <DownloadTaskInfo>[];
  }

  return decoded
      .whereType<Map>()
      .map(
        (Map<dynamic, dynamic> item) =>
            DownloadTaskInfo.fromJson(Map<String, dynamic>.from(item)),
      )
      .toList(growable: false);
}

class DownloadManager extends ChangeNotifier {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;

  static const int _maxActiveDownloads = 1;
  static const int _maxActiveSeedsWhenIdle = 1;
  static const int _normalPeerCap = 22;
  static const int _playbackPeerCap = 32;
  static const int _tailPeerCap = 34;
  static const int _seedPeerCap = 6;
  static const double _lowSpeedThresholdKb = 96.0;
  static const Duration _speedSampleInterval = Duration(seconds: 3);
  static const Duration _maintenanceInterval = Duration(seconds: 20);
  static const Duration _peerRefreshCooldown = Duration(seconds: 35);

  final Map<String, TorrentTask> _activeTasks = <String, TorrentTask>{};
  final Map<String, DownloadTaskInfo> _taskConfigs =
      <String, DownloadTaskInfo>{};
  final Map<String, bool> _pausedStates = <String, bool>{};
  final Map<String, bool> _queuedStates = <String, bool>{};
  final Map<String, int> _lastDownloadedBytes = <String, int>{};
  final Map<String, DateTime> _lastSpeedSampleTimes = <String, DateTime>{};
  final Map<String, double> _currentSpeeds = <String, double>{};
  final Map<String, double> _currentUploadSpeeds = <String, double>{};
  final Map<String, double> _lastNotifiedProgress = <String, double>{};
  final Map<String, double> _lastNotifiedSpeeds = <String, double>{};
  final Map<String, double> _lastNotifiedUploadSpeeds = <String, double>{};
  final Map<String, DateTime> _lastPeerRefreshTimes = <String, DateTime>{};
  final Map<String, Timer> _peerWarmupTimers = <String, Timer>{};
  final Set<String> _streamOptimizedTasks = <String>{};

  String? _playbackPriorityHash;
  bool _isScheduling = false;
  Timer? _speedTimer;
  Timer? _maintenanceTimer;
  final DownloadTaskRepository _taskRepository =
      DownloadTaskRepository.instance;

  DownloadManager._internal() {
    _speedTimer = Timer.periodic(_speedSampleInterval, _calculateSpeeds);
    _maintenanceTimer = Timer.periodic(
      _maintenanceInterval,
      _maintainActiveTransfers,
    );
  }

  List<DownloadTaskInfo> get allTasks => _taskConfigs.values.toList();
  bool hasTask(String hash) => _activeTasks.containsKey(hash);

  Future<void> initPersistedTasks() async {
    final List<DownloadTaskInfo> persistedTasks =
        await _loadPersistedTaskConfigs();
    bool hasMigratedTask = false;

    if (persistedTasks.isEmpty) {
      return;
    }

    for (DownloadTaskInfo info in persistedTasks) {
      final File torrentFile = File('${info.savePath}/meta.torrent');
      if (!await torrentFile.exists()) {
        await _taskRepository.deleteByHash(info.hash);
        continue;
      }

      try {
        final Uint8List bytes = await torrentFile.readAsBytes();
        final Torrent torrent = await Torrent.parseFromBytes(bytes);

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

        final TorrentTask task = TorrentTask.newTask(torrent, info.savePath);
        _activeTasks[info.hash] = task;
        _taskConfigs[info.hash] = info;
        _pausedStates[info.hash] = info.isPaused;
        _queuedStates[info.hash] = false;
        _lastDownloadedBytes[info.hash] = task.downloaded ?? 0;
        _lastSpeedSampleTimes[info.hash] = DateTime.now();
        _currentSpeeds[info.hash] = 0.0;
        _currentUploadSpeeds[info.hash] = 0.0;
        _lastNotifiedProgress[info.hash] = info.isCompleted ? 1.0 : 0.0;
        _lastNotifiedSpeeds[info.hash] = 0.0;
        _lastNotifiedUploadSpeeds[info.hash] = 0.0;
      } catch (error) {
        debugPrint('Failed to restore task: $error');
      }
    }

    if (hasMigratedTask) {
      await _persistAllTasks();
    }
    await _enforceConcurrency();
    _syncBackgroundService();
    notifyListeners();
  }

  Future<List<DownloadTaskInfo>> _loadPersistedTaskConfigs() async {
    final List<DownloadTaskInfo> databaseTasks = await _taskRepository
        .loadAll();
    if (databaseTasks.isNotEmpty) {
      return databaseTasks;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? legacyJson = prefs.getString('anime_saved_tasks');
    if (legacyJson == null || legacyJson.trim().isEmpty) {
      return <DownloadTaskInfo>[];
    }

    try {
      final List<DownloadTaskInfo> legacyTasks = await compute(
        _decodeLegacyDownloadTasks,
        legacyJson,
      );
      await _taskRepository.upsertAll(legacyTasks);
      await prefs.remove('anime_saved_tasks');
      return legacyTasks;
    } catch (error) {
      debugPrint('Failed to migrate legacy download tasks: $error');
      return <DownloadTaskInfo>[];
    }
  }

  Future<void> _persistTask(String hash) async {
    final DownloadTaskInfo? task = _taskConfigs[hash];
    if (task == null) {
      return;
    }
    await _taskRepository.upsert(task);
  }

  Future<void> _persistAllTasks() {
    return _taskRepository.upsertAll(_taskConfigs.values);
  }

  void _calculateSpeeds(Timer timer) {
    final DateTime now = DateTime.now();
    bool shouldNotify = false;

    for (final MapEntry<String, TorrentTask> entry in _activeTasks.entries) {
      final String hash = entry.key;
      final TorrentTask task = entry.value;
      final DownloadTaskInfo? config = _taskConfigs[hash];
      if (config == null) {
        continue;
      }

      final double progress = config.isCompleted
          ? 1.0
          : task.progress.clamp(0.0, 1.0).toDouble();
      final bool isInactive =
          _pausedStates[hash] == true || _queuedStates[hash] == true;

      if (!config.isCompleted && progress >= 1.0) {
        config.isCompleted = true;
        config.isPaused = false;
        _pausedStates[hash] = false;
        _queuedStates[hash] = false;
        _peerWarmupTimers.remove(hash)?.cancel();
        _currentSpeeds[hash] = 0.0;
        _currentUploadSpeeds[hash] = _uploadSpeedInKb(task);
        unawaited(_persistTask(hash));
        unawaited(_enforceConcurrency());
        shouldNotify |= _markVisibleTransferChange(
          hash,
          progress: 1.0,
          downloadSpeed: 0.0,
          uploadSpeed: _currentUploadSpeeds[hash] ?? 0.0,
          force: true,
        );
        continue;
      }

      if (isInactive) {
        _currentSpeeds[hash] = 0.0;
        _currentUploadSpeeds[hash] = 0.0;
        shouldNotify |= _markVisibleTransferChange(
          hash,
          progress: progress,
          downloadSpeed: 0.0,
          uploadSpeed: 0.0,
        );
        continue;
      }

      if (config.isCompleted) {
        _currentSpeeds[hash] = 0.0;
        _currentUploadSpeeds[hash] = _uploadSpeedInKb(task);
        shouldNotify |= _markVisibleTransferChange(
          hash,
          progress: 1.0,
          downloadSpeed: 0.0,
          uploadSpeed: _currentUploadSpeeds[hash] ?? 0.0,
        );
        continue;
      }

      final int currentBytes = task.downloaded ?? 0;
      final int lastBytes = _lastDownloadedBytes[hash] ?? currentBytes;
      final DateTime lastSample =
          _lastSpeedSampleTimes[hash] ?? now.subtract(_speedSampleInterval);
      final double elapsedSeconds = math.max(
        1.0,
        now.difference(lastSample).inMilliseconds / 1000.0,
      );
      final double deltaSpeed =
          ((currentBytes - lastBytes) / 1024.0) / elapsedSeconds;
      final double peerSpeed = task.currentDownloadSpeed;
      final double speed = math.max(peerSpeed, deltaSpeed);

      _currentSpeeds[hash] = speed > 0 ? speed : 0.0;
      _currentUploadSpeeds[hash] = _uploadSpeedInKb(task);
      _lastDownloadedBytes[hash] = currentBytes;
      _lastSpeedSampleTimes[hash] = now;

      shouldNotify |= _markVisibleTransferChange(
        hash,
        progress: progress,
        downloadSpeed: _currentSpeeds[hash] ?? 0.0,
        uploadSpeed: _currentUploadSpeeds[hash] ?? 0.0,
      );
    }

    if (shouldNotify) {
      notifyListeners();
    }
  }

  Future<void> addTask(
    DownloadTaskInfo info,
    Uint8List torrentBytes, {
    bool streamOptimized = false,
  }) async {
    if (_activeTasks.containsKey(info.hash)) {
      final DownloadTaskInfo? existingConfig = _taskConfigs[info.hash];
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
          isPaused: false,
        );
        _pausedStates[info.hash] = false;
        _queuedStates[info.hash] = false;
        await _startOrResumeTask(info.hash, preferred: streamOptimized);
        await _persistTask(info.hash);
        notifyListeners();
      }
      return;
    }

    final Directory targetDir = Directory(info.savePath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final File torrentFile = File('${info.savePath}/meta.torrent');
    if (!await torrentFile.exists()) {
      await torrentFile.writeAsBytes(torrentBytes);
    }

    final Torrent torrent = await Torrent.parseFromBytes(torrentBytes);
    _injectTrackersToTorrent(torrent, info.url);

    if (streamOptimized) {
      _streamOptimizedTasks.add(info.hash);
    }

    final TorrentTask task = TorrentTask.newTask(
      torrent,
      info.savePath,
      streamOptimized,
    );

    _activeTasks[info.hash] = task;
    _taskConfigs[info.hash] = info;
    info.isPaused = false;
    _pausedStates[info.hash] = false;
    _queuedStates[info.hash] = false;
    _lastDownloadedBytes[info.hash] = 0;
    _lastSpeedSampleTimes[info.hash] = DateTime.now();
    _currentSpeeds[info.hash] = 0.0;
    _currentUploadSpeeds[info.hash] = 0.0;
    _lastNotifiedProgress[info.hash] = 0.0;
    _lastNotifiedSpeeds[info.hash] = 0.0;
    _lastNotifiedUploadSpeeds[info.hash] = 0.0;

    await _startOrResumeTask(info.hash, preferred: streamOptimized);
    await _persistTask(info.hash);
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
    _lastSpeedSampleTimes[hash] = DateTime.now();
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
    await _persistTask(hash);
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
      if (task.connectedPeersNumber < 6) {
        _requestPeerSources(task, trackerLimit: 6);
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

  void _maintainActiveTransfers(Timer timer) {
    for (final MapEntry<String, TorrentTask> entry in _activeTasks.entries) {
      final String hash = entry.key;
      final TorrentTask task = entry.value;
      final DownloadTaskInfo? config = _taskConfigs[hash];
      if (config == null ||
          task.state != TaskState.running ||
          _pausedStates[hash] == true ||
          _queuedStates[hash] == true) {
        continue;
      }

      final double progress = config.isCompleted
          ? 1.0
          : task.progress.clamp(0.0, 1.0).toDouble();
      final int peerCap = _peerCapFor(hash, config, progress);
      unawaited(
        _trimPeerLoad(hash, task, peerCap, seeding: config.isCompleted),
      );
      if (!config.isCompleted) {
        _refreshPeerSourcesIfNeeded(hash, task, progress);
      }
    }
  }

  int _peerCapFor(String hash, DownloadTaskInfo config, double progress) {
    if (config.isCompleted) {
      return _seedPeerCap;
    }
    if (hash == _playbackPriorityHash) {
      return _playbackPeerCap;
    }
    if (progress >= 0.85) {
      return _tailPeerCap;
    }
    return _normalPeerCap;
  }

  void _refreshPeerSourcesIfNeeded(
    String hash,
    TorrentTask task,
    double progress,
  ) {
    final double speed = getSpeed(hash);
    final bool tailStage = progress >= 0.85;
    final bool peerShortage = task.connectedPeersNumber < (tailStage ? 18 : 8);
    final bool speedPoor =
        speed < (tailStage ? _lowSpeedThresholdKb * 2 : _lowSpeedThresholdKb);

    if (!peerShortage && !speedPoor) {
      return;
    }

    final DateTime now = DateTime.now();
    final DateTime? lastRefresh = _lastPeerRefreshTimes[hash];
    if (lastRefresh != null &&
        now.difference(lastRefresh) < _peerRefreshCooldown) {
      return;
    }

    _lastPeerRefreshTimes[hash] = now;
    _requestPeerSources(task, trackerLimit: tailStage ? 8 : 4);
  }

  Future<void> _trimPeerLoad(
    String hash,
    TorrentTask task,
    int maxPeers, {
    required bool seeding,
  }) async {
    final List<Peer> peers =
        task.activePeers
            ?.where((Peer peer) => !peer.isDisposed)
            .toList(growable: false) ??
        <Peer>[];
    if (peers.length <= maxPeers) {
      return;
    }

    if (seeding) {
      for (final Peer peer in peers.where((Peer peer) => peer.isSeeder)) {
        peer.sendInterested(false);
        peer.sendChoke(true);
      }
    }

    final List<Peer> disposablePeers =
        peers.where((Peer peer) => !peer.isSeeder).toList(growable: false)
          ..sort(
            (Peer a, Peer b) => _peerScore(
              a,
              seeding: seeding,
            ).compareTo(_peerScore(b, seeding: seeding)),
          );
    final int trimCount = math.min(
      peers.length - maxPeers,
      disposablePeers.length,
    );
    for (final Peer peer in disposablePeers.take(trimCount)) {
      try {
        await peer.dispose(BadException('AnimeMaster peer load shedding'));
      } catch (_) {}
    }
  }

  double _peerScore(Peer peer, {required bool seeding}) {
    double score = peer.currentDownloadSpeed + peer.averageDownloadSpeed * 0.25;
    if (seeding) {
      if (!peer.isSeeder) {
        score += 400;
      }
      if (peer.interestedMe) {
        score += 300;
      }
      score += peer.averageUploadSpeed * 0.2;
    } else {
      if (peer.isSeeder) {
        score += 600;
      }
      if (!peer.chokeMe) {
        score += 150;
      }
      if (peer.requestBuffer.isNotEmpty) {
        score += 80;
      }
    }

    switch (peer.source) {
      case PeerSource.tracker:
        score += 30;
      case PeerSource.dht:
        score += 20;
      case PeerSource.incoming:
        score += 15;
      case PeerSource.pex:
      case PeerSource.lsd:
      case PeerSource.manual:
      case PeerSource.holepunch:
        score += 10;
    }
    return score;
  }

  bool _markVisibleTransferChange(
    String hash, {
    required double progress,
    required double downloadSpeed,
    required double uploadSpeed,
    bool force = false,
  }) {
    final double? lastProgress = _lastNotifiedProgress[hash];
    final double? lastSpeed = _lastNotifiedSpeeds[hash];
    final double? lastUploadSpeed = _lastNotifiedUploadSpeeds[hash];

    final bool progressChanged =
        lastProgress == null ||
        (progress - lastProgress).abs() >= 0.001 ||
        (progress >= 1.0 && lastProgress < 1.0);
    final bool speedChanged =
        lastSpeed == null ||
        (downloadSpeed - lastSpeed).abs() >= 16.0 ||
        (downloadSpeed == 0.0 && lastSpeed > 0.0) ||
        (downloadSpeed > 0.0 && lastSpeed == 0.0);
    final bool uploadSpeedChanged =
        lastUploadSpeed == null ||
        (uploadSpeed - lastUploadSpeed).abs() >= 16.0 ||
        (uploadSpeed == 0.0 && lastUploadSpeed > 0.0) ||
        (uploadSpeed > 0.0 && lastUploadSpeed == 0.0);

    if (!force && !progressChanged && !speedChanged && !uploadSpeedChanged) {
      return false;
    }

    _lastNotifiedProgress[hash] = progress;
    _lastNotifiedSpeeds[hash] = downloadSpeed;
    _lastNotifiedUploadSpeeds[hash] = uploadSpeed;
    return true;
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
      final double progress = activeTask.progress.clamp(0.0, 1.0).toDouble();
      final int peerCap = _peerCapFor(hash, activeConfig, progress);
      final bool needsMorePeers =
          activeTask.connectedPeersNumber < math.min(12, peerCap) ||
          getSpeed(hash) < _lowSpeedThresholdKb;
      if (needsMorePeers) {
        _requestPeerSources(activeTask, trackerLimit: ticks <= 2 ? 8 : 4);
      } else {
        activeTask.requestPeersFromDHT();
      }

      if (ticks >= 8 || activeTask.connectedPeersNumber >= peerCap) {
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
        .map((Uri uri) => uri.toString())
        .toSet();

    for (final String tracker in TrackerPool.robustTrackers) {
      if (!existingTrackers.contains(tracker)) {
        try {
          torrent.announces.add(Uri.parse(tracker));
          existingTrackers.add(tracker);
        } catch (_) {}
      }
    }

    final RegExp trRegex = RegExp(r'&tr=([^&]+)');
    final Iterable<RegExpMatch> matches = trRegex.allMatches(magnetUrl);
    for (final RegExpMatch match in matches) {
      final String tr = Uri.decodeComponent(match.group(1)!);
      if (!existingTrackers.contains(tr)) {
        try {
          torrent.announces.add(Uri.parse(tr));
          existingTrackers.add(tr);
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

    TorrentFile targetFile = torrent.files.first;
    int maxSize = -1;

    for (final TorrentFile file in torrent.files) {
      final String lowerName = file.name.toLowerCase();
      final bool isVideo = videoExtensions.any(lowerName.endsWith);
      if (isVideo && file.length > maxSize) {
        maxSize = file.length;
        targetFile = file;
      }
    }

    if (maxSize < 0) {
      for (final TorrentFile file in torrent.files) {
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

  double getProgress(String hash) {
    if (_taskConfigs[hash]?.isCompleted == true) {
      return 1.0;
    }
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
    final TorrentTask? task = _activeTasks[hash];
    final DownloadTaskInfo? config = _taskConfigs[hash];
    if (task == null || config == null) {
      return;
    }

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
    await _persistTask(hash);
    _syncBackgroundService();
    notifyListeners();
  }

  Future<void> deleteTask(String hash) async {
    final TorrentTask? task = _activeTasks[hash];
    final DownloadTaskInfo? config = _taskConfigs[hash];

    task?.stop();
    _peerWarmupTimers.remove(hash)?.cancel();
    _activeTasks.remove(hash);
    _taskConfigs.remove(hash);
    _pausedStates.remove(hash);
    _queuedStates.remove(hash);
    _streamOptimizedTasks.remove(hash);
    _lastDownloadedBytes.remove(hash);
    _lastSpeedSampleTimes.remove(hash);
    _lastPeerRefreshTimes.remove(hash);
    _currentSpeeds.remove(hash);
    _currentUploadSpeeds.remove(hash);
    _lastNotifiedProgress.remove(hash);
    _lastNotifiedSpeeds.remove(hash);
    _lastNotifiedUploadSpeeds.remove(hash);
    if (_playbackPriorityHash == hash) {
      _playbackPriorityHash = null;
    }

    if (config != null) {
      try {
        final Directory dir = Directory(config.savePath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}
    }

    await _taskRepository.deleteByHash(hash);
    await _enforceConcurrency();
    _syncBackgroundService();
    notifyListeners();
  }

  double _uploadSpeedInKb(TorrentTask task) {
    final double peerUploadSpeed = task.uploadSpeed;
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
    _maintenanceTimer?.cancel();
    for (final Timer timer in _peerWarmupTimers.values) {
      timer.cancel();
    }
    _peerWarmupTimers.clear();
    for (final TorrentTask task in _activeTasks.values) {
      task.stop();
    }
    unawaited(BackgroundDownloadService.setActive(false));
    super.dispose();
  }
}

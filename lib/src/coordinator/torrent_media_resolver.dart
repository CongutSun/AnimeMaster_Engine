import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:flutter/foundation.dart';

import '../api/bangumi_api.dart';
import '../config/embedded_credentials.dart';
import '../managers/download_manager.dart';
import '../models/download_task_info.dart';
import '../utils/app_storage_paths.dart';
import '../utils/magnet_optimizer.dart';
import '../utils/episode_helpers.dart';
import '../utils/task_title_parser.dart';
import '../utils/torrent_cache_fetcher.dart';
import '../services/torrent_metadata_service.dart';

class ResolvedMediaInfo {
  final String title;
  final String filePath;
  final int fileSize;
  final String infoHash;
  final String relativePath;
  final String episodeLabel;

  ResolvedMediaInfo({
    required this.title,
    required this.filePath,
    required this.fileSize,
    required this.infoHash,
    required this.relativePath,
    this.episodeLabel = '',
  });

  String get fileName {
    final String normalized = relativePath.replaceAll('\\', '/');
    final List<String> segments = normalized.split('/');
    return segments.isEmpty ? relativePath : segments.last;
  }
}

class PreparedTorrentTask {
  final DownloadTaskInfo taskInfo;
  final Uint8List torrentBytes;
  final ResolvedMediaInfo mediaInfo;
  final List<ResolvedMediaInfo> mediaItems;
  final int initialIndex;

  PreparedTorrentTask({
    required this.taskInfo,
    required this.torrentBytes,
    required this.mediaInfo,
    required this.mediaItems,
    required this.initialIndex,
  });
}

class _ResolvedBangumiEpisode {
  final String label;
  final int episodeId;

  const _ResolvedBangumiEpisode({this.label = '', this.episodeId = 0});
}

class TorrentMediaResolver {
  static final Dio _torrentDio = Dio(
    BaseOptions(connectTimeout: const Duration(seconds: 15)),
  );
  static const List<String> _videoExtensions = <String>[
    '.mp4',
    '.mkv',
    '.avi',
    '.flv',
    '.rmvb',
    '.ts',
    '.m2ts',
    '.wmv',
    '.webm',
    '.m4v',
  ];

  Future<PreparedTorrentTask> prepareTask(
    String rawSource, {
    String preferredTitle = '',
    String subjectTitle = '',
    String episodeLabel = '',
    int bangumiSubjectId = 0,
    int bangumiEpisodeId = 0,
    String fallbackSource = '',
    CancelToken? cancelToken,
    ValueChanged<String>? onStage,
  }) async {
    final String normalizedSource = rawSource.trim();
    if (normalizedSource.isEmpty) {
      throw Exception('下载源为空，无法解析。');
    }

    final String optimizedSource =
        normalizedSource.toLowerCase().startsWith('http')
        ? normalizedSource
        : MagnetOptimizer.optimize(normalizedSource);

    onStage?.call('正在获取资源文件信息…');
    Uint8List torrentBytes;
    try {
      torrentBytes = await _loadTorrentBytes(
        optimizedSource,
        cancelToken,
        onStage,
      );
    } catch (error) {
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      if (fallbackSource.isEmpty || fallbackSource == rawSource) rethrow;
      onStage?.call('直链暂不可用，正在尝试磁力链接…');
      torrentBytes = await _loadTorrentBytes(
        MagnetOptimizer.optimize(fallbackSource),
        cancelToken,
        onStage,
      );
    }
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    final Torrent torrent = await Torrent.parseFromBytes(torrentBytes);
    final List<TorrentFile> playableFiles = _collectPlayableFiles(torrent);

    if (playableFiles.isEmpty) {
      throw Exception('该种子内没有可播放的媒体文件。');
    }

    final String infoHash = torrent.infoHash.toUpperCase();
    final Directory saveDir = await AppStoragePaths.torrentTaskDirectory(
      infoHash,
    );
    final String effectiveTitle = preferredTitle.trim().isNotEmpty
        ? preferredTitle.trim()
        : (torrent.name.isNotEmpty ? torrent.name : '下载任务_$infoHash');
    final String resolvedSubjectTitle = subjectTitle.trim();
    final String inferredEpisodeLabel = episodeLabel.trim().isNotEmpty
        ? episodeLabel.trim()
        : TaskTitleParser.extractEpisodeLabel(effectiveTitle);
    final _ResolvedBangumiEpisode resolvedEpisode =
        await _resolveBangumiEpisodeMetadata(
          subjectId: bangumiSubjectId,
          explicitEpisodeId: bangumiEpisodeId,
          episodeHint: inferredEpisodeLabel,
          displayTitle: effectiveTitle,
        );
    final String resolvedEpisodeLabel = resolvedEpisode.label.isNotEmpty
        ? resolvedEpisode.label
        : inferredEpisodeLabel;
    final int resolvedBangumiEpisodeId = resolvedEpisode.episodeId > 0
        ? resolvedEpisode.episodeId
        : bangumiEpisodeId;
    final String canonicalSource =
        normalizedSource.toLowerCase().startsWith('http')
        ? MagnetOptimizer.optimize(infoHash)
        : optimizedSource;

    final List<ResolvedMediaInfo> mediaItems =
        playableFiles
            .map(
              (TorrentFile file) => _buildMediaInfo(
                file: file,
                infoHash: infoHash,
                savePath: saveDir.path,
                fallbackTitle: effectiveTitle,
                subjectTitle: resolvedSubjectTitle,
                totalFiles: playableFiles.length,
              ),
            )
            .toList()
          ..sort(
            (ResolvedMediaInfo left, ResolvedMediaInfo right) => left
                .relativePath
                .toLowerCase()
                .compareTo(right.relativePath.toLowerCase()),
          );

    final int initialIndex = _resolveInitialIndex(
      mediaItems: mediaItems,
      episodeHint: resolvedEpisodeLabel,
    );
    final ResolvedMediaInfo mediaInfo = mediaItems[initialIndex];

    final DownloadTaskInfo taskInfo = DownloadTaskInfo(
      hash: infoHash,
      title: effectiveTitle,
      url: canonicalSource,
      savePath: saveDir.path,
      targetPath: mediaInfo.filePath,
      targetSize: mediaInfo.fileSize,
      subjectTitle: resolvedSubjectTitle,
      episodeLabel: resolvedEpisodeLabel,
      bangumiSubjectId: bangumiSubjectId,
      bangumiEpisodeId: resolvedBangumiEpisodeId,
    );

    return PreparedTorrentTask(
      taskInfo: taskInfo,
      torrentBytes: torrentBytes,
      mediaInfo: mediaInfo,
      mediaItems: mediaItems,
      initialIndex: initialIndex,
    );
  }

  Future<ResolvedMediaInfo> resolveAndPrepare(
    String rawSource, {
    String preferredTitle = '',
    String subjectTitle = '',
    String episodeLabel = '',
    int bangumiSubjectId = 0,
    int bangumiEpisodeId = 0,
  }) async {
    final PreparedTorrentTask preparedTask = await prepareTask(
      rawSource,
      preferredTitle: preferredTitle,
      subjectTitle: subjectTitle,
      episodeLabel: episodeLabel,
      bangumiSubjectId: bangumiSubjectId,
      bangumiEpisodeId: bangumiEpisodeId,
    );
    await DownloadManager().addTask(
      preparedTask.taskInfo,
      preparedTask.torrentBytes,
      streamOptimized: true,
    );
    return preparedTask.mediaInfo;
  }

  Future<Uint8List> _loadTorrentBytes(
    String source,
    CancelToken? cancelToken,
    ValueChanged<String>? onStage,
  ) async {
    if (source.toLowerCase().startsWith('http')) {
      final bytes = await _fetchTorrentFromUrl(source, cancelToken);
      await Torrent.parseFromBytes(bytes);
      return bytes;
    }

    String hash = TorrentCacheFetcher.extractHash(source);
    if (hash.isEmpty) {
      throw Exception('下载链接格式无效，无法提取种子哈希。');
    }

    if (hash.length == 32) {
      hash = TorrentCacheFetcher.base32ToHex(hash);
    }

    final Uint8List? cachedBytes = await _readCachedTorrentBytes(hash);
    if (cachedBytes != null && cachedBytes.isNotEmpty) {
      try {
        final parsed = await Torrent.parseFromBytes(cachedBytes);
        if (parsed.infoHash.toUpperCase() == hash) return cachedBytes;
      } catch (_) {
        /* Try network if the local metadata is damaged. */
      }
    }

    final Uint8List? fetchedBytes =
        await TorrentCacheFetcher.fetchFromHttpCache(
          source,
          cancelToken: cancelToken,
        );
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    if (fetchedBytes != null) return fetchedBytes;
    onStage?.call('正在连接种子节点获取文件信息，最长约 60 秒…');
    return TorrentMetadataService().fetch(
      source,
      hash,
      cancelToken: cancelToken,
    );
  }

  Future<Uint8List?> _readCachedTorrentBytes(String hash) async {
    final Directory persistentDir = await AppStoragePaths.torrentTaskDirectory(
      hash,
    );
    final List<File> candidates = <File>[
      File('${persistentDir.path}${Platform.pathSeparator}meta.torrent'),
      File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}AnimeMaster'
        '${Platform.pathSeparator}$hash${Platform.pathSeparator}meta.torrent',
      ),
    ];

    for (final File file in candidates) {
      if (await file.exists()) {
        try {
          return await file.readAsBytes();
        } catch (_) {
          continue;
        }
      }
    }

    return null;
  }

  Future<Uint8List> _fetchTorrentFromUrl(
    String url,
    CancelToken? cancelToken,
  ) async {
    final List<String> candidateUrls = _buildCandidateTorrentUrls(url);
    Object? lastError;

    for (final String candidateUrl in candidateUrls) {
      try {
        if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
        final bytes = await _fetchTorrentCandidate(candidateUrl, cancelToken);
        await Torrent.parseFromBytes(bytes);
        return bytes;
      } catch (error) {
        lastError = error;
        debugPrint('[TorrentMediaResolver] Torrent candidate failed.');
      }
    }

    if (lastError is Exception) {
      throw lastError;
    }
    throw Exception('HTTP torrent download failed.');
  }

  Future<Uint8List> _fetchTorrentCandidate(
    String url,
    CancelToken? cancelToken,
  ) async {
    try {
      final Response<dynamic> response = await _torrentDio.get<dynamic>(
        url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: _isPublicTorrentUrl(url),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 15),
          headers: const <String, String>{
            'Accept': 'application/x-bittorrent,application/octet-stream,*/*',
          },
        ),
      );

      final int? statusCode = response.statusCode;
      if (statusCode == null || statusCode < 200 || statusCode >= 300) {
        throw Exception('HTTP 种子下载失败，状态码：$statusCode');
      }

      final dynamic data = response.data;
      final Uint8List bytes = data is Uint8List
          ? data
          : Uint8List.fromList(List<int>.from(data as List));

      if (bytes.isEmpty) {
        throw Exception('HTTP 种子内容为空。');
      }
      if (bytes.first != 100) {
        throw Exception('返回内容不是合法的 .torrent 文件。');
      }

      return bytes;
    } on DioException {
      throw Exception('HTTP 种子下载失败，请检查网络与资源地址是否有效。');
    }
  }

  List<String> _buildCandidateTorrentUrls(String url) {
    final Uri? uri = Uri.tryParse(url);
    final String host = uri?.host.toLowerCase() ?? '';
    final List<String> candidates = <String>[url];
    if (!_isPublicTorrentUrl(url)) return candidates;

    if (host == 'mikanani.me') {
      final String mirrorUrl = url.replaceAll('mikanani.me', 'mikanime.tv');
      candidates.add(mirrorUrl);
      candidates.add(_proxyUrl('torrent', url));
      candidates.add(_proxyUrl('torrent', mirrorUrl));
    } else if (host == 'mikanime.tv') {
      final String mirrorUrl = url.replaceAll('mikanime.tv', 'mikanani.me');
      candidates.add(mirrorUrl);
      candidates.add(_proxyUrl('torrent', url));
      candidates.add(_proxyUrl('torrent', mirrorUrl));
    } else if (host == 'share.dmhy.org') {
      candidates.add(_proxyUrl('torrent', url));
    }

    return candidates.toSet().toList();
  }

  static bool _isPublicTorrentUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        !uri.hasQuery &&
        uri.userInfo.isEmpty &&
        ['mikanani.me', 'mikanime.tv', 'share.dmhy.org'].contains(uri.host) &&
        RegExp(r'/[a-fA-F0-9]{40}\.torrent$').hasMatch(uri.path);
  }

  String _proxyUrl(String mode, String targetUrl) {
    final String baseUrl = EmbeddedCredentials.resourceProxyBaseUrl.trim();
    if (baseUrl.isEmpty) {
      return targetUrl;
    }
    return '${baseUrl.replaceFirst(RegExp(r'/$'), '')}/proxy/$mode?url=${Uri.encodeComponent(targetUrl)}';
  }

  List<TorrentFile> _collectPlayableFiles(Torrent torrent) {
    final List<TorrentFile> videos = torrent.files.where((TorrentFile file) {
      final String fileName = file.name.toLowerCase();
      return _videoExtensions.any(fileName.endsWith);
    }).toList();

    if (videos.isNotEmpty) {
      return videos;
    }

    return torrent.files.where((TorrentFile file) => file.length > 0).toList();
  }

  ResolvedMediaInfo _buildMediaInfo({
    required TorrentFile file,
    required String infoHash,
    required String savePath,
    required String fallbackTitle,
    required String subjectTitle,
    required int totalFiles,
  }) {
    final String cleanedName = TaskTitleParser.stripSourcePrefix(
      _removeExtension(_basename(file.path)),
    );
    final String extractedEpisode = TaskTitleParser.extractEpisodeLabel(
      cleanedName,
    );
    final String title = totalFiles == 1
        ? fallbackTitle
        : _buildEpisodeTitle(
            fallbackTitle: fallbackTitle,
            subjectTitle: subjectTitle,
            cleanedName: cleanedName,
            episodeLabel: extractedEpisode,
          );

    return ResolvedMediaInfo(
      title: title,
      filePath: _buildAbsoluteFilePath(savePath, file.path),
      fileSize: file.length,
      infoHash: infoHash,
      relativePath: file.path,
      episodeLabel: extractedEpisode,
    );
  }

  String _buildEpisodeTitle({
    required String fallbackTitle,
    required String subjectTitle,
    required String cleanedName,
    required String episodeLabel,
  }) {
    if (subjectTitle.trim().isNotEmpty && episodeLabel.trim().isNotEmpty) {
      return '${subjectTitle.trim()} $episodeLabel';
    }
    if (cleanedName.trim().isNotEmpty) {
      return cleanedName.trim();
    }
    return fallbackTitle;
  }

  Future<_ResolvedBangumiEpisode> _resolveBangumiEpisodeMetadata({
    required int subjectId,
    required int explicitEpisodeId,
    required String episodeHint,
    required String displayTitle,
  }) async {
    if (subjectId <= 0) {
      return const _ResolvedBangumiEpisode();
    }

    try {
      final List<Map<String, dynamic>> episodes = await BangumiApi.instance
          .getSubjectEpisodes(subjectId);
      if (episodes.isEmpty) {
        return const _ResolvedBangumiEpisode();
      }

      Map<String, dynamic>? match;
      if (explicitEpisodeId > 0) {
        match = episodes.firstWhere(
          (Map<String, dynamic> item) =>
              int.tryParse(item['id']?.toString() ?? '') == explicitEpisodeId,
          orElse: () => <String, dynamic>{},
        );
        if (match.isEmpty) {
          match = null;
        }
      }

      final int? episodeNumber = TaskTitleParser.extractEpisodeNumber(
        '$episodeHint $displayTitle',
      );
      if (match == null && episodeNumber != null) {
        match = episodes.firstWhere(
          (Map<String, dynamic> item) =>
              _numberValue(item['ep']) == episodeNumber ||
              _numberValue(item['sort']) == episodeNumber,
          orElse: () => <String, dynamic>{},
        );
        if (match.isEmpty) {
          match = null;
        }
      }

      if (match == null) {
        return const _ResolvedBangumiEpisode();
      }

      final int number =
          _numberValue(match['ep']) ?? _numberValue(match['sort']) ?? 0;
      final String episodeTitle =
          (match['name_cn']?.toString().trim().isNotEmpty == true
                  ? match['name_cn']
                  : match['name'])
              ?.toString()
              .trim() ??
          '';
      return _ResolvedBangumiEpisode(
        label: TaskTitleParser.buildEpisodeDisplayLabel(
          episodeNumber: number,
          episodeTitle: episodeTitle,
        ),
        episodeId: int.tryParse(match['id']?.toString() ?? '') ?? 0,
      );
    } catch (error) {
      debugPrint('[TorrentMediaResolver] Episode metadata failed: $error');
      return const _ResolvedBangumiEpisode();
    }
  }

  int? _numberValue(dynamic value) => safeInt(value);

  int _resolveInitialIndex({
    required List<ResolvedMediaInfo> mediaItems,
    required String episodeHint,
  }) {
    if (mediaItems.isEmpty) {
      return 0;
    }

    final String normalizedHint = _normalizeForMatch(episodeHint);
    if (normalizedHint.isNotEmpty) {
      for (int index = 0; index < mediaItems.length; index++) {
        final ResolvedMediaInfo item = mediaItems[index];
        final String title = _normalizeForMatch(item.title);
        final String path = _normalizeForMatch(item.relativePath);
        if (title.contains(normalizedHint) || path.contains(normalizedHint)) {
          return index;
        }
      }
    }

    int bestIndex = 0;
    int maxSize = -1;
    for (int index = 0; index < mediaItems.length; index++) {
      if (mediaItems[index].fileSize > maxSize) {
        maxSize = mediaItems[index].fileSize;
        bestIndex = index;
      }
    }
    return bestIndex;
  }

  String _normalizeForMatch(String value) {
    return value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  }

  String _basename(String path) {
    final String normalized = path.replaceAll('\\', '/');
    final List<String> segments = normalized.split('/');
    return segments.isEmpty ? path : segments.last;
  }

  String _removeExtension(String fileName) {
    final int index = fileName.lastIndexOf('.');
    if (index <= 0) {
      return fileName;
    }
    return fileName.substring(0, index);
  }

  String _buildAbsoluteFilePath(String basePath, String relativePath) {
    final String normalizedRelative = relativePath.replaceAll(
      '/',
      Platform.pathSeparator,
    );
    return '$basePath${Platform.pathSeparator}$normalizedRelative';
  }
}

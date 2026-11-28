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
import '../services/cache_episode_index.dart';
import 'package:path/path.dart' as p;
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
  final bool uniquelyMatched;

  PreparedTorrentTask({
    required this.taskInfo,
    required this.torrentBytes,
    required this.mediaInfo,
    required this.mediaItems,
    required this.initialIndex,
    this.uniquelyMatched = false,
  });
}

class TorrentMediaResolver {
  TorrentMediaResolver({
    Dio? client,
    this.directoryFor = AppStoragePaths.torrentTaskDirectory,
  }) : _client = client ?? _torrentDio;
  final Dio _client;
  final Future<Directory> Function(String) directoryFor;
  static final Dio _torrentDio = Dio(
    BaseOptions(connectTimeout: const Duration(seconds: 15)),
  );
  Future<PreparedTorrentTask> prepareTask(
    String rawSource, {
    String preferredTitle = '',
    String subjectTitle = '',
    String episodeLabel = '',
    int bangumiSubjectId = 0,
    int bangumiEpisodeId = 0,
    String fallbackSource = '',
    List<String> alternatives = const [],
    String expectedHash = '',
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
    Uint8List? accepted;
    Torrent? parsed;
    final routes = {
      optimizedSource,
      ...alternatives.where((e) => e.startsWith('https://')),
      if (fallbackSource.isNotEmpty) MagnetOptimizer.optimize(fallbackSource),
    };
    final expected = expectedHash.isNotEmpty
        ? expectedHash
        : TorrentCacheFetcher.canonicalHash(
            fallbackSource.isNotEmpty ? fallbackSource : normalizedSource,
          );
    Object? lastError;
    for (final route in routes) {
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      try {
        if (route != optimizedSource) onStage?.call('正在尝试备用入口…');
        final bytes = await _loadTorrentBytes(route, cancelToken, onStage);
        final result = await Torrent.parseFromBytes(bytes);
        if (expected.isNotEmpty &&
            result.infoHash.toUpperCase() != expected.toUpperCase()) {
          throw const FormatException('种子文件与资源哈希不一致');
        }
        accepted = bytes;
        parsed = result;
        break;
      } catch (error) {
        lastError = error;
      }
    }
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    if (accepted == null || parsed == null) {
      throw lastError ?? StateError('所有下载入口暂不可用');
    }
    final torrentBytes = accepted;
    final torrent = parsed;
    final String infoHash = torrent.infoHash.toUpperCase();
    final Directory saveDir = await directoryFor(infoHash);
    final String effectiveTitle = preferredTitle.trim().isNotEmpty
        ? preferredTitle.trim()
        : (torrent.name.isNotEmpty ? torrent.name : '下载任务_$infoHash');
    final String resolvedSubjectTitle = subjectTitle.trim();
    List<Map<String, dynamic>> catalog = [];
    if (bangumiSubjectId > 0) {
      try {
        catalog = await BangumiApi.instance.getSubjectEpisodes(
          bangumiSubjectId,
        );
      } catch (_) {}
    }
    final files = CacheEpisodeIndex.torrent(
      torrent,
      saveDir.path,
      resolvedSubjectTitle,
      catalog,
      releaseTitle: effectiveTitle,
    );
    if (files.isEmpty) throw const FormatException('该种子内没有可播放的视频文件。');
    final String canonicalSource =
        normalizedSource.toLowerCase().startsWith('http')
        ? MagnetOptimizer.optimize(infoHash)
        : optimizedSource;

    final mediaItems = [
      for (final f in files)
        ResolvedMediaInfo(
          title: f.label,
          filePath: f.path,
          fileSize: f.size,
          infoHash: infoHash,
          relativePath: p.relative(f.path, from: saveDir.path),
          episodeLabel: f.label,
        ),
    ];
    final wanted = TaskTitleParser.extractEpisodeNumber(episodeLabel);
    final matches = files.indexed
        .where(
          (entry) =>
              (bangumiEpisodeId > 0 &&
                  entry.$2.episodeId == bangumiEpisodeId) ||
              (wanted != null && wanted == entry.$2.number),
        )
        .toList();
    final initialIndex = matches.length == 1 ? matches.single.$1 : 0;
    final ResolvedMediaInfo mediaInfo = mediaItems[initialIndex];

    final DownloadTaskInfo taskInfo = DownloadTaskInfo(
      hash: infoHash,
      title: effectiveTitle,
      url: canonicalSource,
      savePath: saveDir.path,
      targetPath: mediaInfo.filePath,
      targetSize: mediaInfo.fileSize,
      subjectTitle: resolvedSubjectTitle,
      files: files,
      episodeLabel: files[initialIndex].label,
      bangumiSubjectId: bangumiSubjectId,
      bangumiEpisodeId: files[initialIndex].episodeId,
    );

    return PreparedTorrentTask(
      taskInfo: taskInfo,
      torrentBytes: torrentBytes,
      mediaInfo: mediaInfo,
      mediaItems: mediaItems,
      initialIndex: initialIndex,
      uniquelyMatched: matches.length == 1,
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
      final Response<dynamic> response = await _client.get<dynamic>(
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
}

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:flutter/foundation.dart';

import '../api/dio_client.dart';
import '../managers/download_manager.dart';
import '../models/download_task_info.dart';
import '../utils/app_storage_paths.dart';
import '../utils/magnet_optimizer.dart';
import '../utils/task_title_parser.dart';
import '../utils/torrent_cache_fetcher.dart';

class ResolvedMediaInfo {
  final String title;
  final String filePath;
  final int fileSize;
  final String infoHash;

  ResolvedMediaInfo({
    required this.title,
    required this.filePath,
    required this.fileSize,
    required this.infoHash,
  });
}

class PreparedTorrentTask {
  final DownloadTaskInfo taskInfo;
  final Uint8List torrentBytes;
  final ResolvedMediaInfo mediaInfo;

  PreparedTorrentTask({
    required this.taskInfo,
    required this.torrentBytes,
    required this.mediaInfo,
  });
}

class TorrentMediaResolver {
  Future<PreparedTorrentTask> prepareTask(
    String rawSource, {
    String preferredTitle = '',
    String subjectTitle = '',
    String episodeLabel = '',
  }) async {
    final String normalizedSource = rawSource.trim();
    if (normalizedSource.isEmpty) {
      throw Exception('下载源为空，无法解析。');
    }

    final String optimizedSource = normalizedSource.toLowerCase().startsWith(
          'http',
        )
        ? normalizedSource
        : MagnetOptimizer.optimize(normalizedSource);

    final Uint8List torrentBytes = await _loadTorrentBytes(optimizedSource);
    final Torrent torrent = await Torrent.parseFromBytes(torrentBytes);

    if (torrent.files.isEmpty) {
      throw Exception('该种子内没有可下载的媒体文件。');
    }

    final String infoHash = torrent.infoHash.toUpperCase();
    final Directory saveDir = await AppStoragePaths.torrentTaskDirectory(
      infoHash,
    );
    final TorrentFile targetFile = _selectPrimaryVideoFile(torrent);
    final String targetFilePath = _buildAbsoluteFilePath(
      saveDir.path,
      targetFile.path,
    );

    final String effectiveTitle = preferredTitle.trim().isNotEmpty
        ? preferredTitle.trim()
        : (torrent.name.isNotEmpty ? torrent.name : '下载任务_$infoHash');
    final String resolvedSubjectTitle = subjectTitle.trim();
    final String resolvedEpisodeLabel = episodeLabel.trim().isNotEmpty
        ? episodeLabel.trim()
        : TaskTitleParser.extractEpisodeLabel(effectiveTitle);
    final String canonicalSource = normalizedSource.toLowerCase().startsWith(
          'http',
        )
        ? MagnetOptimizer.optimize(infoHash)
        : optimizedSource;

    final DownloadTaskInfo taskInfo = DownloadTaskInfo(
      hash: infoHash,
      title: effectiveTitle,
      url: canonicalSource,
      savePath: saveDir.path,
      targetPath: targetFilePath,
      subjectTitle: resolvedSubjectTitle,
      episodeLabel: resolvedEpisodeLabel,
    );

    final ResolvedMediaInfo mediaInfo = ResolvedMediaInfo(
      title: effectiveTitle,
      filePath: targetFilePath,
      fileSize: targetFile.length,
      infoHash: infoHash,
    );

    return PreparedTorrentTask(
      taskInfo: taskInfo,
      torrentBytes: torrentBytes,
      mediaInfo: mediaInfo,
    );
  }

  Future<ResolvedMediaInfo> resolveAndPrepare(
    String rawSource, {
    String preferredTitle = '',
    String subjectTitle = '',
    String episodeLabel = '',
  }) async {
    final PreparedTorrentTask preparedTask = await prepareTask(
      rawSource,
      preferredTitle: preferredTitle,
      subjectTitle: subjectTitle,
      episodeLabel: episodeLabel,
    );
    await DownloadManager().addTask(
      preparedTask.taskInfo,
      preparedTask.torrentBytes,
    );
    return preparedTask.mediaInfo;
  }

  Future<Uint8List> _loadTorrentBytes(String source) async {
    if (source.toLowerCase().startsWith('http')) {
      return _fetchTorrentFromUrl(source);
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
      return cachedBytes;
    }

    final Uint8List? fetchedBytes = await TorrentCacheFetcher.fetchFromHttpCache(
      source,
    );
    if (fetchedBytes == null || fetchedBytes.isEmpty) {
      throw Exception(
        '无法获取种子元数据。当前资源未提供直链，且公共缓存节点未返回有效 .torrent 文件。'
        '建议优先选择带 .torrent 直链的检索结果，或稍后重试。',
      );
    }

    return fetchedBytes;
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

  Future<Uint8List> _fetchTorrentFromUrl(String url) async {
    try {
      final Response<dynamic> response = await DioClient().dio.get<dynamic>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
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
    } on DioException catch (error) {
      debugPrint('[TorrentMediaResolver] HTTP torrent fetch failed: $error');
      final Object? inner = error.error;
      if (inner is Exception) {
        throw inner;
      }
      throw Exception('HTTP 种子下载失败：${error.message ?? '未知错误'}');
    }
  }

  TorrentFile _selectPrimaryVideoFile(Torrent torrent) {
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
      '.m4v',
    ];

    TorrentFile targetFile = torrent.files.first;
    int maxSize = -1;

    for (final TorrentFile file in torrent.files) {
      final String fileName = file.name.toLowerCase();
      final bool isVideo = videoExtensions.any(fileName.endsWith);
      if (isVideo && file.length > maxSize) {
        maxSize = file.length;
        targetFile = file;
      }
    }

    if (maxSize >= 0) {
      return targetFile;
    }

    for (final TorrentFile file in torrent.files) {
      if (file.length > maxSize) {
        maxSize = file.length;
        targetFile = file;
      }
    }

    return targetFile;
  }

  String _buildAbsoluteFilePath(String basePath, String relativePath) {
    final String normalizedRelative = relativePath.replaceAll(
      '/',
      Platform.pathSeparator,
    );
    return '$basePath${Platform.pathSeparator}$normalizedRelative';
  }
}

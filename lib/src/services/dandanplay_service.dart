import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../models/dandanplay_models.dart';

class DandanplayService {
  static const String _baseUrl = 'https://api.dandanplay.net';
  static const int _chunkSize = 16 * 1024 * 1024;
  static const int _maxMatchCacheSize = 200;
  static const int _maxCommentCacheSize = 50;

  /// Bounded LRU caches to prevent unbounded memory growth.
  static final LinkedHashMap<String, DandanplayMatchResult> _matchCache =
      LinkedHashMap<String, DandanplayMatchResult>();
  static final LinkedHashMap<String, DandanplayMatchResult> _manualMatchCache =
      LinkedHashMap<String, DandanplayMatchResult>();
  static final LinkedHashMap<int, List<DandanplayComment>> _commentCache =
      LinkedHashMap<int, List<DandanplayComment>>();

  static void _cacheMatch(String key, DandanplayMatchResult value) {
    _matchCache[key] = value;
    if (_matchCache.length > _maxMatchCacheSize) {
      _matchCache.remove(_matchCache.keys.first);
    }
  }

  static void _cacheManualMatch(String key, DandanplayMatchResult value) {
    _manualMatchCache[key] = value;
    if (_manualMatchCache.length > _maxMatchCacheSize) {
      _manualMatchCache.remove(_manualMatchCache.keys.first);
    }
  }

  static void _cacheComments(int episodeId, List<DandanplayComment> value) {
    _commentCache[episodeId] = value;
    if (_commentCache.length > _maxCommentCacheSize) {
      _commentCache.remove(_commentCache.keys.first);
    }
  }

  final String appId;
  final String appSecret;
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      responseType: ResponseType.json,
      followRedirects: true,
    ),
  );

  DandanplayService({required this.appId, required this.appSecret});

  bool get isConfigured =>
      appId.trim().isNotEmpty && appSecret.trim().isNotEmpty;

  Future<DandanplayLoadResult> loadDanmaku({
    required String displayTitle,
    String localFilePath = '',
    String subjectTitle = '',
    String episodeLabel = '',
  }) async {
    if (!isConfigured) {
      throw Exception('请先在设置中填写弹弹play 的 AppId 和 AppSecret。');
    }

    final DandanplayMatchResult match = await _resolveMatch(
      displayTitle: displayTitle,
      localFilePath: localFilePath,
      subjectTitle: subjectTitle,
      episodeLabel: episodeLabel,
    );
    final List<DandanplayComment> comments = await _loadComments(
      match.episodeId,
      shiftSeconds: match.shift,
    );
    return DandanplayLoadResult(match: match, comments: comments);
  }

  Future<DandanplayLoadResult> loadDanmakuFromMatch(
    DandanplayMatchResult match,
  ) async {
    final List<DandanplayComment> comments = await _loadComments(
      match.episodeId,
      shiftSeconds: match.shift,
    );
    return DandanplayLoadResult(match: match, comments: comments);
  }

  Future<List<DandanplayMatchResult>> searchEpisodeCandidates({
    required String animeKeyword,
    String episodeKeyword = '',
  }) async {
    if (!isConfigured) {
      throw Exception('请先在设置中填写弹弹play 的 AppId 和 AppSecret。');
    }

    final String trimmedAnime = animeKeyword.trim();
    final String trimmedEpisode = episodeKeyword.trim();
    if (trimmedAnime.length < 2) {
      return <DandanplayMatchResult>[];
    }

    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/v2/search/episodes',
      queryParameters: <String, dynamic>{
        'anime': trimmedAnime,
        if (trimmedEpisode.isNotEmpty) 'episode': trimmedEpisode,
      },
      options: Options(headers: _buildHeaders('/api/v2/search/episodes')),
    );

    final dynamic data = response.data;
    if (response.statusCode != 200 || data is! Map<String, dynamic>) {
      throw Exception('弹弹play 搜索接口返回异常。');
    }

    final List<dynamic> animes = data['animes'] is List
        ? data['animes'] as List<dynamic>
        : <dynamic>[];
    final List<DandanplayMatchResult> results = <DandanplayMatchResult>[];
    for (final dynamic anime in animes) {
      if (anime is! Map) {
        continue;
      }
      final Map<String, dynamic> animeMap = Map<String, dynamic>.from(anime);
      final List<dynamic> episodes = animeMap['episodes'] is List
          ? animeMap['episodes'] as List<dynamic>
          : <dynamic>[];
      for (final dynamic episode in episodes) {
        if (episode is! Map) {
          continue;
        }
        final Map<String, dynamic> episodeMap = Map<String, dynamic>.from(
          episode,
        );
        results.add(
          DandanplayMatchResult(
            episodeId:
                int.tryParse(episodeMap['episodeId']?.toString() ?? '') ?? 0,
            animeId: int.tryParse(animeMap['animeId']?.toString() ?? '') ?? 0,
            animeTitle: animeMap['animeTitle']?.toString() ?? '',
            episodeTitle: episodeMap['episodeTitle']?.toString() ?? '',
            shift: double.tryParse(episodeMap['shift']?.toString() ?? '') ?? 0,
          ),
        );
      }
    }
    return results
        .where((DandanplayMatchResult item) => item.episodeId > 0)
        .toList();
  }

  void rememberManualMatch({
    required String displayTitle,
    required String localFilePath,
    required String subjectTitle,
    required String episodeLabel,
    required DandanplayMatchResult match,
  }) {
    final String cacheKey = _buildCacheKey(
      displayTitle: displayTitle,
      localFilePath: localFilePath,
      subjectTitle: subjectTitle,
      episodeLabel: episodeLabel,
    );
    _cacheManualMatch(cacheKey, match);
    _cacheMatch(cacheKey, match);
  }

  String buildSuggestedAnimeKeyword({
    required String displayTitle,
    String subjectTitle = '',
  }) {
    return _buildAnimeKeyword(
      subjectTitle: subjectTitle,
      displayTitle: displayTitle,
    );
  }

  String buildSuggestedEpisodeKeyword({
    required String displayTitle,
    String episodeLabel = '',
  }) {
    return _buildEpisodeKeyword(
      episodeLabel: episodeLabel,
      displayTitle: displayTitle,
    );
  }

  Future<DandanplayMatchResult> _resolveMatch({
    required String displayTitle,
    required String localFilePath,
    required String subjectTitle,
    required String episodeLabel,
  }) async {
    final String cacheKey = _buildCacheKey(
      displayTitle: displayTitle,
      localFilePath: localFilePath,
      subjectTitle: subjectTitle,
      episodeLabel: episodeLabel,
    );
    final DandanplayMatchResult? manual = _manualMatchCache[cacheKey];
    if (manual != null) {
      return manual;
    }
    final DandanplayMatchResult? cached = _matchCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    DandanplayMatchResult? match;
    if (localFilePath.trim().isNotEmpty && await File(localFilePath).exists()) {
      match = await _matchByFile(localFilePath);
    }
    match ??= await _searchByTitle(
      displayTitle: displayTitle,
      subjectTitle: subjectTitle,
      episodeLabel: episodeLabel,
    );

    if (match == null || match.episodeId <= 0) {
      throw Exception('未能在弹弹play 中匹配到对应节目。');
    }

    _cacheMatch(cacheKey, match);
    return match;
  }

  Future<DandanplayMatchResult?> _matchByFile(String filePath) async {
    final File file = File(filePath);
    final int fileSize = await file.length();
    if (fileSize <= 0) {
      return null;
    }

    final String fileName = _stripExtension(file.uri.pathSegments.last);
    final String fileHash = await _computeFirstChunkMd5(file);

    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/v2/match',
      data: <String, dynamic>{
        'fileName': fileName,
        'fileHash': fileHash,
        'fileSize': fileSize,
        'matchMode': fileHash.isEmpty ? 'fileNameOnly' : 'hashAndFileName',
      },
      options: Options(headers: _buildHeaders('/api/v2/match')),
    );

    final dynamic data = response.data;
    if (response.statusCode != 200 || data is! Map<String, dynamic>) {
      return null;
    }

    final List<dynamic> matches = data['matches'] is List
        ? data['matches'] as List<dynamic>
        : <dynamic>[];
    if (matches.isEmpty) {
      return null;
    }

    return DandanplayMatchResult.fromJson(
      Map<String, dynamic>.from(matches.first as Map),
    );
  }

  Future<DandanplayMatchResult?> _searchByTitle({
    required String displayTitle,
    required String subjectTitle,
    required String episodeLabel,
  }) async {
    final String animeKeyword = _buildAnimeKeyword(
      subjectTitle: subjectTitle,
      displayTitle: displayTitle,
    );
    final String episodeKeyword = _buildEpisodeKeyword(
      episodeLabel: episodeLabel,
      displayTitle: displayTitle,
    );
    final List<DandanplayMatchResult> candidates =
        await searchEpisodeCandidates(
          animeKeyword: animeKeyword,
          episodeKeyword: episodeKeyword,
        );
    return candidates.isEmpty ? null : candidates.first;
  }

  Future<List<DandanplayComment>> _loadComments(
    int episodeId, {
    required double shiftSeconds,
  }) async {
    final List<DandanplayComment>? cached = _commentCache[episodeId];
    if (cached != null) {
      return _applyShift(cached, shiftSeconds);
    }

    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/v2/comment/$episodeId',
      queryParameters: const <String, dynamic>{
        'withRelated': true,
        'chConvert': 1,
      },
      options: Options(headers: _buildHeaders('/api/v2/comment/$episodeId')),
    );

    final dynamic data = response.data;
    if (response.statusCode != 200 || data is! Map<String, dynamic>) {
      throw Exception('弹弹play 弹幕接口返回异常。');
    }

    final List<DandanplayComment> comments =
        ((data['comments'] as List<dynamic>? ?? <dynamic>[]))
            .whereType<Map>()
            .map(
              (Map<dynamic, dynamic> item) =>
                  DandanplayComment.fromJson(Map<String, dynamic>.from(item)),
            )
            .where((DandanplayComment item) => item.text.trim().isNotEmpty)
            .toList()
          ..sort(
            (DandanplayComment left, DandanplayComment right) =>
                left.appearAt.compareTo(right.appearAt),
          );

    _cacheComments(episodeId, comments);
    return _applyShift(comments, shiftSeconds);
  }

  List<DandanplayComment> _applyShift(
    List<DandanplayComment> comments,
    double shiftSeconds,
  ) {
    if (shiftSeconds == 0) {
      return comments;
    }

    final Duration offset = Duration(
      milliseconds: (shiftSeconds * 1000).round(),
    );
    return comments
        .map((DandanplayComment item) => item.shiftBy(offset))
        .toList();
  }

  Map<String, String> _buildHeaders(String path) {
    final int timestamp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final String payload = '$appId$timestamp${path.toLowerCase()}$appSecret';
    final String signature = base64.encode(
      sha256.convert(utf8.encode(payload)).bytes,
    );

    return <String, String>{
      'X-AppId': appId.trim(),
      'X-Timestamp': '$timestamp',
      'X-Signature': signature,
      'Accept': 'application/json',
    };
  }

  Future<String> _computeFirstChunkMd5(File file) async {
    final RandomAccessFile raf = await file.open();
    try {
      final int size = await raf.length();
      final int bytesToRead = size < _chunkSize ? size : _chunkSize;
      final List<int> bytes = await raf.read(bytesToRead);
      return md5.convert(bytes).toString();
    } finally {
      await raf.close();
    }
  }

  String _buildCacheKey({
    required String displayTitle,
    required String localFilePath,
    required String subjectTitle,
    required String episodeLabel,
  }) {
    return '${localFilePath.trim()}|${displayTitle.trim()}|${subjectTitle.trim()}|${episodeLabel.trim()}';
  }

  String _buildAnimeKeyword({
    required String subjectTitle,
    required String displayTitle,
  }) {
    final String seed = subjectTitle.trim().isNotEmpty
        ? subjectTitle.trim()
        : displayTitle.trim();
    String normalized = seed
        .replaceAll(RegExp(r'^\[[^\]]+\]\s*'), '')
        .replaceAll(RegExp(r'\[[^\]]+\]'), ' ')
        .replaceAll(RegExp(r'\([^\)]*\)'), ' ')
        .replaceAll(
          RegExp(
            r'\b(1080p|720p|x264|x265|hevc|aac|gb|big5|mp4|mkv)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\bS\d{1,2}E\d{1,3}\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\bEP?\s*\d+\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (normalized.length < 2) {
      normalized = seed.trim();
    }
    return normalized;
  }

  String _buildEpisodeKeyword({
    required String episodeLabel,
    required String displayTitle,
  }) {
    final String seed = '${episodeLabel.trim()} ${displayTitle.trim()}'.trim();
    final RegExpMatch? seasonMatch = RegExp(
      r'\bS\d{1,2}E(\d{1,3})\b',
      caseSensitive: false,
    ).firstMatch(seed);
    if (seasonMatch != null) {
      return seasonMatch.group(1) ?? '';
    }

    final RegExpMatch? episodeMatch = RegExp(
      r'(?<!\d)(\d{1,3})(?!\d)',
    ).firstMatch(seed);
    if (episodeMatch != null) {
      return episodeMatch.group(1) ?? '';
    }

    if (seed.toLowerCase().contains('movie')) {
      return 'movie';
    }
    return '';
  }

  String _stripExtension(String fileName) {
    final int index = fileName.lastIndexOf('.');
    if (index <= 0) {
      return fileName;
    }
    return fileName.substring(0, index);
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dandanplay_models.dart';
import 'dandanplay_cache.dart';

class DandanplayService {
  DandanplayService({
    this.appId = '',
    this.appSecret = '',
    Dio? dio,
    DandanplayCache? cache,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 35),
               sendTimeout: const Duration(seconds: 20),
             ),
           ),
       _cache = cache ?? DandanplayCache();

  static const String gatewayUrl = 'https://auth.congutsun.com/dandanplay';
  final String appId;
  final String appSecret;
  final Dio _dio;
  final DandanplayCache _cache;
  bool get usesGateway => appId.trim().isEmpty || appSecret.trim().isEmpty;
  bool get isConfigured => true;
  String get _namespace => usesGateway ? 'gateway-v1' : 'app-${appId.trim()}';
  static Future<void> _manualWrites = Future<void>.value();

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    Map<String, String>? extraHeaders,
  }) async {
    if (!path.startsWith('/api/v2/') && path != '/capabilities') {
      throw const DandanplayException('接口路径无效。');
    }
    final base = usesGateway ? gatewayUrl : 'https://api.dandanplay.net';
    try {
      final response = await _dio.request<dynamic>(
        '$base$path',
        queryParameters: query,
        data: body,
        options: Options(
          method: body == null ? 'GET' : 'POST',
          headers: {
            ...(usesGateway
                ? <String, String>{'Accept': 'application/json'}
                : _buildHeaders(path)),
            ...?extraHeaders,
          },
        ),
      );
      final data = response.data;
      if (data is! Map) throw const DandanplayException('弹幕服务返回的数据无法识别。');
      final map = Map<String, dynamic>.from(data);
      if (map['success'] == false ||
          (map['errorCode'] != null && map['errorCode'] != 0)) {
        throw DandanplayException(
          map['errorMessage']?.toString() ?? '弹幕服务未能完成请求。',
          code: map['errorCode']?.toString() ?? '',
        );
      }
      return map;
    } on DioException catch (error) {
      final data = error.response?.data;
      final code = data is Map ? data['errorCode']?.toString() ?? '' : '';
      final message = data is Map ? data['errorMessage']?.toString() : null;
      throw DandanplayException(
        message ??
            switch (error.response?.statusCode) {
              401 || 403 => '弹弹play暂未授权此操作，请检查服务配置。',
              429 => '弹幕服务的共享额度或访问频率受限，请稍后重试。',
              _ => '暂时无法连接弹幕服务，请稍后重试。',
            },
        code: code,
        status: error.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> capabilities() => usesGateway
      ? request('/capabilities')
      : Future.value({'success': true, 'send': true, 'account': false});

  Future<DandanplayLoadResult> loadDanmaku({
    required String displayTitle,
    String localFilePath = '',
    String subjectTitle = '',
    String episodeLabel = '',
    int bangumiSubjectId = 0,
    bool fileReady = false,
    bool forceReload = false,
  }) async {
    final match = await _resolveMatch(
      displayTitle: displayTitle,
      localFilePath: localFilePath,
      subjectTitle: subjectTitle,
      episodeLabel: episodeLabel,
      bangumiSubjectId: bangumiSubjectId,
      fileReady: fileReady,
    );
    return loadDanmakuFromMatch(match, forceReload: forceReload);
  }

  Future<DandanplayLoadResult> loadDanmakuFromMatch(
    DandanplayMatchResult match, {
    bool forceReload = false,
  }) async {
    final key = '$_namespace:comments:${match.episodeId}';
    Map<String, dynamic>? data = forceReload ? null : await _cache.read(key);
    bool stale = false;
    if (data == null) {
      try {
        data = await request(
          '/api/v2/comment/${match.episodeId}',
          query: {'withRelated': true, 'chConvert': 1},
        );
        await _cache.write(key, data, const Duration(minutes: 5));
      } on DandanplayException catch (error) {
        if (error.status == 401 || error.status == 403) rethrow;
        data = await _cache.read(key, allowExpired: true);
        if (data == null) rethrow;
        stale = true;
      }
    }
    final comments =
        (data['comments'] as List? ?? [])
            .whereType<Map>()
            .map(
              (item) =>
                  DandanplayComment.fromJson(Map<String, dynamic>.from(item)),
            )
            .where(
              (item) =>
                  item.text.trim().isNotEmpty &&
                  item.appearAt.inSeconds <= 86400,
            )
            .map(
              (item) => item.shiftBy(
                Duration(milliseconds: (match.shift * 1000).round()),
              ),
            )
            .toList()
          ..sort((a, b) => a.appearAt.compareTo(b.appearAt));
    return DandanplayLoadResult(
      match: match,
      comments: comments,
      isStale: stale,
    );
  }

  Future<List<DandanplayMatchResult>> searchEpisodeCandidates({
    required String animeKeyword,
    String episodeKeyword = '',
  }) async {
    final anime = animeKeyword.trim();
    if (anime.length < 2) return [];
    final episode = normalizeEpisode(episodeKeyword);
    final key = '$_namespace:search:$anime:$episode';
    var data = await _cache.read(key);
    if (data == null) {
      data = await request(
        '/api/v2/search/episodes',
        query: {
          'anime': anime,
          if (episode.isNotEmpty) 'episode': episode,
          'v2': true,
        },
      );
      await _cache.write(key, data, const Duration(minutes: 30));
    }
    final results = <DandanplayMatchResult>[];
    for (final anime in (data['animes'] as List? ?? []).whereType<Map>()) {
      for (final episode
          in (anime['episodes'] as List? ?? []).whereType<Map>()) {
        final match = DandanplayMatchResult.fromJson({
          ...Map<String, dynamic>.from(episode),
          'animeId': anime['animeId'],
          'animeTitle': anime['animeTitle'],
        });
        if (match.episodeId > 0) results.add(match);
      }
    }
    return results;
  }

  Future<Map<String, dynamic>> details(
    String animeId, {
    bool bangumi = false,
  }) async {
    if (!RegExp(r'^\d{1,12}$').hasMatch(animeId)) {
      throw const DandanplayException('作品编号无效。');
    }
    final path = bangumi
        ? '/api/v2/bangumi/bgmtv/$animeId'
        : '/api/v2/bangumi/$animeId';
    final key = '$_namespace:$path';
    final cached = await _cache.read(key);
    if (cached != null) return cached;
    final data = await request(path);
    await _cache.write(key, data, const Duration(hours: 6));
    return data;
  }

  Future<Map<String, dynamic>> discovery({
    String category = 'hot',
    String period = 'week',
  }) async {
    final path = switch (category) {
      'rising' => '/api/v2/trending/all/rising/$period',
      'new' => '/api/v2/trending/new-anime/hot/current-season',
      'season' => '/api/v2/bangumi/shin',
      _ => '/api/v2/trending/all/hot/$period',
    };
    final key = '$_namespace:$path';
    final cached = await _cache.read(key);
    if (cached != null) return cached;
    final data = await request(
      path,
      query: {
        'filterAdultContent': true,
        if (category != 'season') 'limit': 30,
      },
    );
    await _cache.write(key, data, const Duration(hours: 1));
    return data;
  }

  Future<void> rememberManualMatch({
    required String displayTitle,
    required String localFilePath,
    required String subjectTitle,
    required String episodeLabel,
    required DandanplayMatchResult match,
  }) {
    final key = _buildCacheKey(
      displayTitle,
      localFilePath,
      subjectTitle,
      episodeLabel,
    );
    final operation = _manualWrites.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> values;
      try {
        values = Map<String, dynamic>.from(
          jsonDecode(prefs.getString('dandanplay_manual_matches_v1') ?? '{}')
              as Map,
        );
      } catch (_) {
        values = {};
      }
      values.remove(key);
      values[key] = match.toJson();
      while (values.length > 200) {
        values.remove(values.keys.first);
      }
      await prefs.setString('dandanplay_manual_matches_v1', jsonEncode(values));
    });
    _manualWrites = operation.catchError((Object _) {});
    return operation;
  }

  Future<DandanplayMatchResult?> _manual(String key) async {
    await _manualWrites;
    try {
      final prefs = await SharedPreferences.getInstance();
      final values =
          jsonDecode(prefs.getString('dandanplay_manual_matches_v1') ?? '{}')
              as Map;
      final value = values[key];
      if (value is Map) {
        final match = DandanplayMatchResult.fromJson(
          Map<String, dynamic>.from(value),
        );
        if (match.episodeId > 0) return match;
      }
    } catch (_) {}
    return null;
  }

  Future<DandanplayMatchResult> _resolveMatch({
    required String displayTitle,
    required String localFilePath,
    required String subjectTitle,
    required String episodeLabel,
    required int bangumiSubjectId,
    required bool fileReady,
  }) async {
    final key = _buildCacheKey(
      displayTitle,
      localFilePath,
      subjectTitle,
      episodeLabel,
    );
    final manual = await _manual(key);
    if (manual != null) return manual;
    final matchKey = 'match:$key:$bangumiSubjectId';
    final cached = await _cache.read(matchKey);
    if (cached != null) return DandanplayMatchResult.fromJson(cached);
    List<DandanplayMatchResult> ambiguous = [];
    DandanplayMatchResult? match;
    Object? lastError;
    if (fileReady && localFilePath.isNotEmpty) {
      try {
        final result = await _matchByFile(localFilePath);
        if (result != null) {
          final candidates = (result['matches'] as List? ?? [])
              .whereType<Map>()
              .map(
                (m) => DandanplayMatchResult.fromJson(
                  Map<String, dynamic>.from(m),
                ),
              )
              .where((m) => m.episodeId > 0)
              .toList();
          if (result['isMatched'] == true && candidates.length == 1) {
            match = candidates.single;
          } else {
            ambiguous = candidates;
          }
        }
      } catch (error) {
        lastError = error;
      }
    }
    if (match == null && bangumiSubjectId > 0) {
      try {
        final data = await details('$bangumiSubjectId', bangumi: true);
        final bangumi = data['bangumi'];
        final episode = buildSuggestedEpisodeKeyword(
          displayTitle: displayTitle,
          episodeLabel: episodeLabel,
        );
        if (bangumi is Map && episode.isNotEmpty) {
          final exact = (bangumi['episodes'] as List? ?? [])
              .whereType<Map>()
              .where(
                (e) =>
                    normalizeEpisode(e['episodeNumber']?.toString() ?? '') ==
                    episode,
              )
              .toList();
          if (exact.length == 1) {
            match = DandanplayMatchResult.fromJson({
              ...Map<String, dynamic>.from(exact.single),
              'animeId': bangumi['animeId'],
              'animeTitle': bangumi['animeTitle'],
            });
          }
        }
      } catch (error) {
        lastError = error;
      }
    }
    if (match == null) {
      try {
        final candidates = await searchEpisodeCandidates(
          animeKeyword: buildSuggestedAnimeKeyword(
            displayTitle: displayTitle,
            subjectTitle: subjectTitle,
          ),
          episodeKeyword: buildSuggestedEpisodeKeyword(
            displayTitle: displayTitle,
            episodeLabel: episodeLabel,
          ),
        );
        if (candidates.length == 1) {
          match = candidates.single;
        } else if (candidates.isNotEmpty) {
          ambiguous = candidates;
        }
      } catch (error) {
        lastError = error;
      }
    }
    if (match == null || match.episodeId <= 0) {
      if (ambiguous.isNotEmpty) throw DandanplayMatchRequired(ambiguous);
      if (lastError != null) throw lastError;
      throw const DandanplayException('未找到对应剧集，请手动匹配弹幕。', code: 'no_match');
    }
    await _cache.write(matchKey, match.toJson(), const Duration(days: 7));
    return match;
  }

  Future<Map<String, dynamic>?> _matchByFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;
    final size = await file.length();
    if (size <= 0) return null;
    final handle = await file.open();
    String hash;
    try {
      hash = md5
          .convert(await handle.read(min(size, 16 * 1024 * 1024)))
          .toString();
    } finally {
      await handle.close();
    }
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    return request(
      '/api/v2/match',
      body: {
        'fileName': dot > 0 ? name.substring(0, dot) : name,
        'fileHash': hash,
        'fileSize': size,
        'matchMode': 'hashAndFileName',
      },
    );
  }

  static String newRequestId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<Map<String, dynamic>> sendComment(
    DandanplayMatchResult match, {
    required String text,
    required Duration position,
    required String requestId,
  }) async {
    final value = text.trim();
    if (value.isEmpty || value.runes.length > 100) {
      throw const DandanplayException('弹幕需为 1–100 个字符。');
    }
    final prefs = await SharedPreferences.getInstance();
    var installation = prefs.getString('dandanplay_installation_v1');
    if (installation == null) {
      installation = newRequestId();
      await prefs.setString('dandanplay_installation_v1', installation);
    }
    final result = await request(
      '/api/v2/comment/${match.episodeId}/app',
      body: {
        'comment': value,
        'time': max(0, position.inMilliseconds / 1000 - match.shift),
        'mode': 1,
        'color': 0xffffff,
        if (!usesGateway)
          'userName': 'AnimeMaster-${installation.substring(0, 8)}',
      },
      extraHeaders: {
        'X-Request-Id': requestId,
        'X-Installation-Id': installation,
      },
    );
    await _cache.remove('$_namespace:comments:${match.episodeId}');
    return result;
  }

  Map<String, String> _buildHeaders(String path) {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return {
      'X-AppId': appId.trim(),
      'X-Timestamp': '$timestamp',
      'X-Signature': base64.encode(
        sha256
            .convert(
              utf8.encode('${appId.trim()}$timestamp$path${appSecret.trim()}'),
            )
            .bytes,
      ),
      'Accept': 'application/json',
    };
  }

  String _buildCacheKey(
    String title,
    String path,
    String subject,
    String episode,
  ) => sha256
      .convert(
        utf8.encode(
          '$_namespace|${path.trim()}|${title.trim()}|${subject.trim()}|${episode.trim()}',
        ),
      )
      .toString();

  String buildSuggestedAnimeKeyword({
    required String displayTitle,
    String subjectTitle = '',
  }) {
    final seed = subjectTitle.trim().isNotEmpty
        ? subjectTitle.trim()
        : displayTitle.trim();
    final normalized = seed
        .replaceAll(RegExp(r'\[[^\]]+\]'), ' ')
        .replaceAll(RegExp(r'\bS\d{1,2}E\d{1,4}\b', caseSensitive: false), ' ')
        .replaceAll(
          RegExp(
            r'\b(?:1080p|720p|2160p|x264|x265|hevc|aac|mp4|mkv)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return normalized.length >= 2 ? normalized : seed;
  }

  static String normalizeEpisode(String value) {
    final clean = value.trim().toUpperCase();
    if (RegExp(r'^\d{1,4}$').hasMatch(clean)) return '${int.parse(clean)}';
    if (RegExp(r'^[CSO]\d{1,4}$').hasMatch(clean)) {
      return '${clean[0]}${int.parse(clean.substring(1))}';
    }
    return '';
  }

  String buildSuggestedEpisodeKeyword({
    required String displayTitle,
    String episodeLabel = '',
  }) {
    final direct = normalizeEpisode(episodeLabel);
    if (direct.isNotEmpty) return direct;
    for (final seed in [episodeLabel, displayTitle]) {
      for (final pattern in [
        RegExp(r'\bS\d{1,2}E(\d{1,4})\b', caseSensitive: false),
        RegExp(r'第\s*(\d{1,4})\s*[话話集]'),
        RegExp(r'\bEP?\s*(\d{1,4})\b', caseSensitive: false),
        RegExp(r'(?:^|\s[-–]\s)(\d{1,4})(?:\s|$|\[)'),
        RegExp(r'\b([CSO]\d{1,4})\b', caseSensitive: false),
      ]) {
        final match = pattern.firstMatch(seed);
        if (match != null) return normalizeEpisode(match.group(1)!);
      }
    }
    return '';
  }
}

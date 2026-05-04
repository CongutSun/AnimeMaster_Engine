import 'package:dio/dio.dart';

import '../api/bangumi_api.dart';
import '../models/dandanplay_models.dart';

class AnimekoDanmakuService {
  static const List<String> _baseUrls = <String>[
    'https://danmaku-cn.myani.org',
    'https://danmaku-global.myani.org',
  ];

  static final Map<int, List<DandanplayComment>> _commentCache =
      <int, List<DandanplayComment>>{};

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      responseType: ResponseType.json,
      followRedirects: true,
      headers: const <String, String>{
        'Accept': 'application/json',
        'User-Agent': 'AnimeMaster/2.1.5',
      },
    ),
  );

  Future<DandanplayLoadResult> loadDanmaku({
    required String displayTitle,
    String subjectTitle = '',
    String episodeLabel = '',
    int bangumiSubjectId = 0,
    int bangumiEpisodeId = 0,
  }) async {
    final int? episodeId = await BangumiApi.instance.resolveEpisodeId(
      subjectId: bangumiSubjectId,
      episodeId: bangumiEpisodeId,
      subjectTitle: subjectTitle,
      episodeLabel: episodeLabel,
      displayTitle: displayTitle,
    );

    if (episodeId == null || episodeId <= 0) {
      throw Exception('未能定位 Bangumi 剧集，暂无法加载 Animeko 公益弹幕。');
    }

    final List<DandanplayComment> comments = await _loadComments(episodeId);
    final String resolvedTitle = subjectTitle.trim().isNotEmpty
        ? subjectTitle.trim()
        : 'Animeko 公益弹幕';
    final String resolvedEpisode = episodeLabel.trim().isNotEmpty
        ? episodeLabel.trim()
        : 'Bangumi #$episodeId';

    return DandanplayLoadResult(
      match: DandanplayMatchResult(
        episodeId: episodeId,
        animeId: bangumiSubjectId,
        animeTitle: resolvedTitle,
        episodeTitle: resolvedEpisode,
      ),
      comments: comments,
    );
  }

  Future<List<DandanplayComment>> _loadComments(int episodeId) async {
    final List<DandanplayComment>? cached = _commentCache[episodeId];
    if (cached != null) {
      return cached;
    }

    Object? lastError;
    for (final String baseUrl in _baseUrls) {
      try {
        final Response<dynamic> response = await _dio.get<dynamic>(
          '$baseUrl/v1/danmaku/$episodeId',
          queryParameters: const <String, dynamic>{'maxCount': 8000},
        );

        final dynamic data = response.data;
        if (response.statusCode != 200 || data is! Map<String, dynamic>) {
          lastError = Exception('Animeko 弹幕接口返回异常。');
          continue;
        }

        final List<dynamic> rawItems = data['danmakuList'] is List
            ? data['danmakuList'] as List<dynamic>
            : <dynamic>[];
        final List<DandanplayComment> comments =
            rawItems
                .whereType<Map>()
                .map((Map<dynamic, dynamic> item) {
                  return Map<String, dynamic>.from(item);
                })
                .map(_parseComment)
                .where((DandanplayComment item) => item.text.trim().isNotEmpty)
                .toList()
              ..sort(
                (DandanplayComment left, DandanplayComment right) =>
                    left.appearAt.compareTo(right.appearAt),
              );

        _commentCache[episodeId] = comments;
        return comments;
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception(
      'Animeko 公益弹幕加载失败：${lastError?.toString().replaceFirst('Exception: ', '') ?? '网络异常'}',
    );
  }

  DandanplayComment _parseComment(Map<String, dynamic> item) {
    final Map<String, dynamic> info = item['danmakuInfo'] is Map
        ? Map<String, dynamic>.from(item['danmakuInfo'] as Map)
        : <String, dynamic>{};
    final int playTimeMs =
        int.tryParse(info['playTime']?.toString() ?? '') ?? 0;
    final int color = int.tryParse(info['color']?.toString() ?? '') ?? 0xFFFFFF;
    final String text = info['text']?.toString() ?? '';
    final String location = info['location']?.toString().toUpperCase() ?? '';
    final int id =
        int.tryParse(item['id']?.toString() ?? '') ??
        ('$playTimeMs|$text').hashCode.abs();

    return DandanplayComment(
      id: id,
      appearAt: Duration(milliseconds: playTimeMs),
      mode: switch (location) {
        'TOP' => 5,
        'BOTTOM' => 4,
        _ => 1,
      },
      color: color,
      userId: item['senderId']?.toString() ?? '',
      text: text,
    );
  }
}

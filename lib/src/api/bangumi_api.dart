import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:flutter/foundation.dart';

import 'api_cache_manager.dart';
import 'api_exceptions.dart';
import 'dio_client.dart';
import '../repositories/anime_repository.dart';
import '../utils/episode_helpers.dart';

class _ApiConfig {
  static const String apiBase = 'https://api.bgm.tv';
  static const String webBase = 'https://bgm.tv';
  static const String chiiBase = 'https://chii.in';
  static const List<String> htmlBases = <String>[chiiBase, webBase];
}

class BangumiApi {
  static final Dio _dio = DioClient().dio;
  static final AnimeRepository _animeRepository = AnimeRepository.instance;

  // ── TTL caches replacing 16 ad‑hoc static Maps ──
  static final ApiCacheManager<Map<String, dynamic>> _animeDetailCache =
      ApiCacheManager<Map<String, dynamic>>(maxSize: 60);
  static final ApiCacheManager<List<dynamic>> _charactersCache =
      ApiCacheManager<List<dynamic>>(maxSize: 60);
  static final ApiCacheManager<List<dynamic>> _personsCache =
      ApiCacheManager<List<dynamic>>(maxSize: 60);
  static final ApiCacheManager<List<dynamic>> _relationsCache =
      ApiCacheManager<List<dynamic>>(maxSize: 60);
  static final ApiCacheManager<List<Map<String, String>>> _commentsCache =
      ApiCacheManager<List<Map<String, String>>>(maxSize: 60);
  static final ApiCacheManager<List<Map<String, String>>>
  _episodeCommentsCache = ApiCacheManager<List<Map<String, String>>>(
    maxSize: 120,
  );
  static final ApiCacheManager<List<dynamic>> _searchCache =
      ApiCacheManager<List<dynamic>>(maxSize: 80);
  static final ApiCacheManager<List<Map<String, dynamic>>> _tagSubjectsCache =
      ApiCacheManager<List<Map<String, dynamic>>>(maxSize: 80);
  static final ApiCacheManager<List<dynamic>> _characterSubjectsCache =
      ApiCacheManager<List<dynamic>>(maxSize: 80);
  static final ApiCacheManager<List<dynamic>> _personSubjectsCache =
      ApiCacheManager<List<dynamic>>(maxSize: 80);
  static final ApiCacheManager<List<Map<String, dynamic>>>
  _subjectEpisodesCache = ApiCacheManager<List<Map<String, dynamic>>>(
    maxSize: 80,
  );
  static final ApiCacheManager<int?> _episodeIdResolveCache =
      ApiCacheManager<int?>(maxSize: 120);

  // Calendar cache is time‑sensitive — invalidate after 1 hour
  static final ApiCacheManager<List<dynamic>> _calendarCache =
      ApiCacheManager<List<dynamic>>(
        maxSize: 1,
        defaultTtl: const Duration(hours: 1),
      );
  static final ApiCacheManager<List<Map<String, dynamic>>> _yearTopCache =
      ApiCacheManager<List<Map<String, dynamic>>>(
        maxSize: 1,
        defaultTtl: const Duration(hours: 6),
      );
  static int? _yearTopCacheYear;

  static List<Map<String, String>> _parseSubjectCommentsDocument(
    dom.Document document,
  ) {
    final List<Map<String, String>> comments = <Map<String, String>>[];
    final Iterable<dom.Element> items = document.querySelectorAll(
      '#comment_box .item, .comment_box .item, #comment_list .item',
    );

    for (final dom.Element item in items) {
      final String author = _firstText(item, <String>[
        '.text a.l',
        '.text > a',
        '.userInfo a.l',
        'a.l',
      ]);
      final String content = _firstText(item, <String>[
        'p.comment',
        '.text p',
        '.comment',
        'p',
      ]);
      String rate = '未评级';

      final dom.Element? starSpan = item.querySelector('.text span.starlight');
      if (starSpan != null) {
        final RegExpMatch? match = RegExp(
          r'stars(\d+)',
        ).firstMatch(starSpan.attributes['class'] ?? '');
        if (match != null) {
          rate = '${match.group(1)}分';
        }
      }

      if (content.isNotEmpty) {
        comments.add(<String, String>{
          'author': author.isEmpty ? '网络用户' : author,
          'rate': rate,
          'content': content,
        });
      }
    }

    return comments;
  }

  static List<Map<String, String>> _parseEpisodeCommentsDocument(
    dom.Document document,
  ) {
    final List<Map<String, String>> comments = <Map<String, String>>[];

    final Iterable<dom.Element> roots = _episodeCommentRoots(document);

    for (final dom.Element item in roots) {
      final Map<String, String>? comment = _parseEpisodeCommentElement(item);
      if (comment != null) {
        comments.add(comment);
      }
      _collectNestedReplies(item, comments);
    }

    return _dedupeEpisodeComments(comments);
  }

  static Iterable<dom.Element> _episodeCommentRoots(dom.Document document) {
    final dom.Element? commentList = document.querySelector('#comment_list');
    if (commentList == null) {
      return const <dom.Element>[];
    }

    final List<dom.Element> directItems = commentList.children
        .where(_isTopLevelCommentContainer)
        .toList(growable: false);
    if (directItems.isNotEmpty) {
      return directItems;
    }

    return commentList
        .querySelectorAll('.row_reply, .item')
        .where((dom.Element item) => !_hasCommentContainerAncestor(item));
  }

  static bool _isTopLevelCommentContainer(dom.Element item) {
    return item.classes.contains('row_reply') || item.classes.contains('item');
  }

  static bool _hasCommentContainerAncestor(dom.Element item) {
    dom.Element? parent = item.parent;
    while (parent != null && parent.id != 'comment_list') {
      if (parent.classes.contains('row_reply') ||
          parent.classes.contains('item') ||
          parent.classes.contains('sub_reply_bg')) {
        return true;
      }
      parent = parent.parent;
    }
    return false;
  }

  /// Walk nested reply chains once. `querySelectorAll` already returns deep
  /// descendants, so recursing here would duplicate楼中楼 replies.
  static void _collectNestedReplies(
    dom.Element parent,
    List<Map<String, String>> out,
  ) {
    List<dom.Element> replies = parent
        .querySelectorAll(
          '.topic_sub_reply .sub_reply_bg, '
          '.sub_reply .sub_reply_bg, '
          '.sub_reply_bg',
        )
        .toList(growable: false);
    if (replies.isEmpty) {
      replies = parent
          .querySelectorAll(
            '.topic_sub_reply .row_reply, .topic_sub_reply .item',
          )
          .toList(growable: false);
    }

    for (final dom.Element reply in replies) {
      final Map<String, String>? subReply = _parseEpisodeCommentElement(
        reply,
        isReply: true,
      );
      if (subReply != null) {
        out.add(subReply);
      }
    }
  }

  static Map<String, String>? _parseEpisodeCommentElement(
    dom.Element item, {
    bool isReply = false,
  }) {
    final String author = _firstText(item, <String>[
      '.inner strong a',
      '.text a',
      '.userInfo strong a',
      'a.l',
      'a',
    ]);
    final String time = _firstText(item, <String>[
      'small.grey',
      'small',
      '.tip_j',
      '.date',
    ]);
    final String content = _episodeCommentContent(item, isReply: isReply);

    if (content.isEmpty) {
      return null;
    }

    return <String, String>{
      'author': author.isEmpty ? '网络用户' : author,
      'time': time,
      'content': content,
      'type': isReply ? 'reply' : 'comment',
    };
  }

  static String _episodeCommentContent(
    dom.Element item, {
    required bool isReply,
  }) {
    final Iterable<String> selectors = isReply
        ? <String>['.cmt_sub_content', '.reply_content', '.message', 'p']
        : <String>['.reply_content', '.message', '.inner > p', 'p'];

    for (final String selector in selectors) {
      final dom.Element? contentElement = item.querySelector(selector);
      if (contentElement == null) {
        continue;
      }
      final String text = _textWithoutNestedReplies(contentElement);
      if (text.isNotEmpty) {
        return text;
      }
    }

    return _textWithoutNestedReplies(item);
  }

  static String _firstText(dom.Element item, Iterable<String> selectors) {
    for (final String selector in selectors) {
      final String text = _compactText(
        item.querySelector(selector)?.text ?? '',
      );
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  static String _textWithoutNestedReplies(dom.Element element) {
    final dom.Document document = parser.parse(element.outerHtml);
    for (final dom.Element nested in document.querySelectorAll(
      '.topic_sub_reply, .sub_reply',
    )) {
      nested.remove();
    }
    return _compactText(
      document.body?.text ?? document.documentElement?.text ?? '',
    );
  }

  static String _compactText(String value) {
    return value
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _decodeHtmlResponse(dynamic data) {
    if (data is String) {
      return data;
    }
    if (data is List<int>) {
      return utf8.decode(data, allowMalformed: true);
    }
    return data?.toString() ?? '';
  }

  static Options _htmlRequestOptions({String referer = _ApiConfig.webBase}) {
    return Options(
      responseType: ResponseType.bytes,
      headers: <String, String>{
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Referer': referer,
      },
    );
  }

  static Future<dom.Document?> _getHtmlDocument(
    String url, {
    String referer = _ApiConfig.webBase,
  }) async {
    final Response<dynamic> response = await _dio.get(
      url,
      options: _htmlRequestOptions(referer: referer),
    );
    final int statusCode = response.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      return null;
    }
    final String html = _decodeHtmlResponse(response.data);
    if (html.trim().isEmpty) {
      return null;
    }
    return parser.parse(html);
  }

  static List<Map<String, String>> _dedupeEpisodeComments(
    List<Map<String, String>> comments,
  ) {
    final Map<String, int> contentIndex = <String, int>{};
    final Set<String> exactSeen = <String>{};
    final List<Map<String, String>> result = <Map<String, String>>[];
    for (final Map<String, String> comment in comments) {
      final String exactKey =
          '${comment['type']}|${comment['author']}|${comment['time']}|${comment['content']}';
      if (!exactSeen.add(exactKey)) {
        continue;
      }

      final String author = comment['author'] ?? '';
      final String contentKey =
          '${comment['type']}|${_compactText(comment['content'] ?? '')}';
      final int? existingIndex = contentIndex[contentKey];
      if (existingIndex != null) {
        final Map<String, String> existing = result[existingIndex];
        final bool existingIsFallback = existing['author'] == '网络用户';
        final bool currentIsFallback = author == '网络用户';
        if (existingIsFallback || currentIsFallback) {
          if (existingIsFallback && !currentIsFallback) {
            result[existingIndex] = comment;
          }
          continue;
        }
      }

      contentIndex.putIfAbsent(contentKey, () => result.length);
      result.add(comment);
    }
    return result;
  }

  // 统一的 HTML 列表解析器，消除冗余代码
  static List<Map<String, dynamic>> _parseBrowserItemList(
    String html,
    int limit,
  ) {
    List<Map<String, dynamic>> results = [];
    final document = parser.parse(html);
    final ul = document.getElementById('browserItemList');

    if (ul != null) {
      final items = ul.getElementsByClassName('item').take(limit);
      for (var item in items) {
        final aTag = item.querySelector('a.l');
        if (aTag == null) continue;

        final sid = aTag.attributes['href']?.split('/').last ?? '';
        final name = aTag.text.trim();
        final scoreTag = item.querySelector('small.fade');
        final score = scoreTag != null ? scoreTag.text.trim() : '暂无数据';

        final imgTag = item.querySelector('img');
        String imgUrl = '';
        if (imgTag != null && imgTag.attributes.containsKey('src')) {
          imgUrl = imgTag.attributes['src']!.replaceAll('/s/', '/l/');
          if (imgUrl.startsWith('//')) imgUrl = 'https:$imgUrl';
        }

        results.add({
          'id': int.tryParse(sid) ?? sid,
          'name': name,
          'rating': {'score': score},
          'images': {'large': imgUrl},
        });
      }
    }
    return results;
  }

  static Future<List<dynamic>> search(
    String keyword, {
    int type = 2,
    int start = 0,
    int maxResults = 25,
  }) async {
    final String cacheKey = '${keyword.trim()}|$type|$start|$maxResults';
    final List<dynamic>? cached = _searchCache.get(cacheKey);
    if (cached != null) return cached;

    try {
      final response = await _dio.get(
        '${_ApiConfig.apiBase}/search/subject/${Uri.encodeComponent(keyword)}',
        queryParameters: {
          'type': type,
          'start': start,
          'max_results': maxResults,
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> results = response.data['list'] is List
            ? response.data['list']
            : <dynamic>[];
        _searchCache.set(cacheKey, results);
        return results;
      }
    } catch (e) {
      debugPrint('[BangumiApi.search] ${e.runtimeType}: $e');
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> getSubjectsByTag(
    String tag, {
    int type = 2,
    int page = 1,
  }) async {
    final String cacheKey = '${tag.trim()}|$type|$page';
    if (_tagSubjectsCache.get(cacheKey) != null) {
      return _tagSubjectsCache.get(cacheKey)!;
    }

    try {
      final typeStr = type == 1 ? 'book' : 'anime';
      final response = await _dio.get(
        '${_ApiConfig.webBase}/$typeStr/tag/${Uri.encodeComponent(tag)}',
        queryParameters: {'page': page},
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode == 200) {
        final List<Map<String, dynamic>> results = _parseBrowserItemList(
          utf8.decode(response.data),
          24,
        );
        _tagSubjectsCache.set(cacheKey, results);
        // cache eviction handled internally by ApiCacheManager
        return results;
      }
    } catch (e) {
      debugPrint('[BangumiApi.getSubjectsByTag] Exception: $e');
    }
    return [];
  }

  static Future<List<dynamic>> getCharacterSubjects(int characterId) async {
    final List<dynamic>? cached = _characterSubjectsCache.get(characterId);
    if (cached != null) return cached;

    try {
      final response = await _dio.get(
        '${_ApiConfig.apiBase}/v0/characters/$characterId/subjects',
      );
      if (response.statusCode == 200) {
        final List<dynamic> results = response.data is List
            ? response.data
            : <dynamic>[];
        _characterSubjectsCache.set(characterId, results);
        return results;
      }
    } catch (e) {
      debugPrint('[BangumiApi.getCharacterSubjects] ${e.runtimeType}: $e');
    }
    return [];
  }

  static Future<List<dynamic>> getPersonSubjects(int personId) async {
    final List<dynamic>? cached = _personSubjectsCache.get(personId);
    if (cached != null) return cached;

    try {
      final response = await _dio.get(
        '${_ApiConfig.apiBase}/v0/persons/$personId/subjects',
      );
      if (response.statusCode == 200) {
        final List<dynamic> results = response.data is List
            ? response.data
            : <dynamic>[];
        _personSubjectsCache.set(personId, results);
        return results;
      }
    } catch (e) {
      debugPrint('[BangumiApi.getPersonSubjects] ${e.runtimeType}: $e');
    }
    return [];
  }

  static Future<List<dynamic>> getCalendar() async {
    final List<dynamic>? cached = _calendarCache.get('calendar');
    if (cached != null) return cached;

    try {
      final response = await _dio.get('${_ApiConfig.apiBase}/calendar');
      if (response.statusCode == 200 && response.data is List) {
        final List<dynamic> results = response.data as List<dynamic>;
        _calendarCache.set('calendar', results);
        return results;
      }
    } catch (e) {
      debugPrint('[BangumiApi.getCalendar] ${e.runtimeType}: $e');
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> getYearTop() async {
    final int year = DateTime.now().year;
    final List<Map<String, dynamic>>? cached = _yearTopCache.get('yearTop');
    if (_yearTopCacheYear == year && cached != null) return cached;

    try {
      var response = await _dio.get(
        '${_ApiConfig.webBase}/anime/browser/airtime/$year',
        queryParameters: {'sort': 'rank'},
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode != 200) {
        response = await _dio.get(
          '${_ApiConfig.webBase}/anime/browser',
          queryParameters: {'sort': 'rank'},
          options: Options(responseType: ResponseType.bytes),
        );
      }

      if (response.statusCode == 200) {
        final List<Map<String, dynamic>> results = _parseBrowserItemList(
          utf8.decode(response.data),
          10,
        );
        _yearTopCache.set('yearTop', results);
        _yearTopCacheYear = year;
        return results;
      }
    } catch (e) {
      debugPrint('[BangumiApi.getYearTop] ${e.runtimeType}: $e');
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> getSubjectEpisodes(
    int subjectId,
  ) async {
    if (subjectId <= 0) return <Map<String, dynamic>>[];
    final List<Map<String, dynamic>>? cached = _subjectEpisodesCache.get(
      subjectId,
    );
    if (cached != null) return cached;

    final List<Map<String, dynamic>> episodes = <Map<String, dynamic>>[];
    int offset = 0;
    const int limit = 100;

    try {
      while (true) {
        final Response<dynamic> response = await _dio.get(
          '${_ApiConfig.apiBase}/v0/episodes',
          queryParameters: <String, dynamic>{
            'subject_id': subjectId,
            'type': 0,
            'limit': limit,
            'offset': offset,
          },
        );
        if (response.statusCode != 200 || response.data is! Map) {
          break;
        }

        final Map<String, dynamic> data = Map<String, dynamic>.from(
          response.data as Map,
        );
        final List<dynamic> page = data['data'] is List
            ? data['data'] as List<dynamic>
            : <dynamic>[];
        episodes.addAll(
          page.whereType<Map>().map((Map<dynamic, dynamic> item) {
            return Map<String, dynamic>.from(item);
          }).toList(),
        );

        final int total = int.tryParse(data['total']?.toString() ?? '') ?? 0;
        offset += page.length;
        if (page.isEmpty || offset >= total) {
          break;
        }
      }
    } catch (e) {
      debugPrint('[BangumiApi.getSubjectEpisodes] Exception: $e');
      final List<Map<String, dynamic>> cachedEpisodes = await _animeRepository
          .loadEpisodes(subjectId);
      if (cachedEpisodes.isNotEmpty) {
        return cachedEpisodes;
      }
    }

    if (episodes.isNotEmpty) {
      unawaited(_animeRepository.upsertEpisodes(subjectId, episodes));
    }
    _subjectEpisodesCache.set(subjectId, episodes);
    return episodes;
  }

  static Future<int?> resolveEpisodeId({
    int subjectId = 0,
    int episodeId = 0,
    String subjectTitle = '',
    String episodeLabel = '',
    String displayTitle = '',
  }) async {
    if (episodeId > 0) {
      return episodeId;
    }

    final String cacheKey =
        '$subjectId|${subjectTitle.trim()}|${episodeLabel.trim()}|${displayTitle.trim()}';
    final int? cachedId = _episodeIdResolveCache.get(cacheKey);
    if (cachedId != null) return cachedId;

    int resolvedSubjectId = subjectId;
    if (resolvedSubjectId <= 0) {
      resolvedSubjectId =
          await _resolveSubjectIdByTitle(
            subjectTitle.trim().isNotEmpty ? subjectTitle : displayTitle,
          ) ??
          0;
    }

    if (resolvedSubjectId <= 0) {
      _episodeIdResolveCache.set(cacheKey, null);
      return null;
    }

    final List<Map<String, dynamic>> episodes = await getSubjectEpisodes(
      resolvedSubjectId,
    );
    if (episodes.isEmpty) {
      _episodeIdResolveCache.set(cacheKey, null);
      return null;
    }

    final int? episodeNumber = _extractEpisodeNumber(
      '${episodeLabel.trim()} ${displayTitle.trim()}',
    );
    Map<String, dynamic>? match;
    if (episodeNumber != null && episodeNumber > 0) {
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

    match ??= episodes.length == 1 ? episodes.first : null;
    final int? resolvedEpisodeId = match == null
        ? null
        : int.tryParse(match['id']?.toString() ?? '');
    _episodeIdResolveCache.set(cacheKey, resolvedEpisodeId);
    return resolvedEpisodeId;
  }

  static Future<int?> _resolveSubjectIdByTitle(String rawTitle) async {
    final String keyword = _sanitizeSubjectKeyword(rawTitle);
    if (keyword.length < 2) {
      return null;
    }

    try {
      final Response<dynamic> response = await _dio.post(
        '${_ApiConfig.apiBase}/v0/search/subjects',
        data: <String, dynamic>{
          'keyword': keyword,
          'filter': <String, dynamic>{
            'type': <int>[2],
          },
        },
      );
      if (response.statusCode != 200 || response.data is! Map) {
        return null;
      }

      final List<dynamic> subjects = (response.data as Map)['data'] is List
          ? (response.data as Map)['data'] as List<dynamic>
          : <dynamic>[];
      final List<Map<String, dynamic>> items = subjects
          .whereType<Map>()
          .map((Map<dynamic, dynamic> item) => Map<String, dynamic>.from(item))
          .toList();
      if (items.isEmpty) {
        return null;
      }

      final String normalizedKeyword = _normalizeTitle(keyword);
      final Map<String, dynamic> best = items.firstWhere(
        (Map<String, dynamic> item) =>
            _normalizeTitle(item['name_cn']?.toString() ?? '') ==
                normalizedKeyword ||
            _normalizeTitle(item['name']?.toString() ?? '') ==
                normalizedKeyword,
        orElse: () => items.first,
      );
      return int.tryParse(best['id']?.toString() ?? '');
    } catch (e) {
      debugPrint('[BangumiApi._resolveSubjectIdByTitle] Exception: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getAnimeDetail(int id) async {
    final Map<String, dynamic>? cached = _animeDetailCache.get(id);
    if (cached != null) return cached;

    try {
      final response = await _dio.get('${_ApiConfig.apiBase}/v0/subjects/$id');
      if (response.statusCode == 200 && response.data is Map) {
        final Map<String, dynamic> detail = Map<String, dynamic>.from(
          response.data as Map,
        );
        _animeDetailCache.set(id, detail);
        unawaited(_animeRepository.upsertSubject(detail));
        return detail;
      }
    } catch (e) {
      debugPrint('[BangumiApi.getAnimeDetail] ${e.runtimeType}: $e');
    }
    return _animeRepository.loadSubject(id);
  }

  static int? _extractEpisodeNumber(String value) =>
      extractEpisodeNumber(value);

  static int? _numberValue(dynamic value) => safeInt(value);

  static String _sanitizeSubjectKeyword(String value) {
    final String cleaned = value
        .replaceAll(RegExp(r'^\[[^\]]+\]\s*'), ' ')
        .replaceAll(RegExp(r'\[[^\]]+\]'), ' ')
        .replaceAll(RegExp(r'\([^\)]*\)'), ' ')
        .replaceAll(
          RegExp(
            r'\b(1080p|720p|2160p|x264|x265|hevc|aac|gb|big5|mp4|mkv|web-dl|webdl|baha|cr)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\bS\d{1,2}E\d{1,3}\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\bEP?\s*\.?\s*\d+\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'第\s*\d{1,3}\s*[话話集回]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isNotEmpty ? cleaned : value.trim();
  }

  static String _normalizeTitle(String value) {
    return value
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('　', '')
        .toLowerCase();
  }

  static Future<Map<String, dynamic>?> getUserCollection(
    int subjectId,
    String username,
    String token,
  ) async {
    if (username.isEmpty || token.isEmpty) return null;
    try {
      final response = await _dio.get(
        '${_ApiConfig.apiBase}/v0/users/$username/collections/$subjectId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200 && response.data is Map) {
        return response.data;
      }
    } catch (e) {
      debugPrint('[BangumiApi.getUserCollection] Exception: $e');
    }
    return null;
  }

  static Future<List<dynamic>> getUserCollectionList(
    String username, {
    int type = 3,
    int subjectType = 2,
  }) async {
    if (username.isEmpty) return [];
    try {
      final response = await _dio.get(
        '${_ApiConfig.apiBase}/v0/users/$username/collections',
        queryParameters: {
          'subject_type': subjectType,
          'type': type,
          'limit': 100,
        },
      );
      if (response.statusCode == 200 && response.data is Map) {
        return response.data['data'] is List ? response.data['data'] : [];
      }
    } catch (e) {
      debugPrint('[BangumiApi.getUserCollectionList] Exception: $e');
    }
    return [];
  }

  static Future<bool> updateCollection(
    int subjectId,
    String token,
    Map<String, dynamic> postData,
  ) async {
    if (token.isEmpty) return false;
    try {
      final response = await _dio.post(
        '${_ApiConfig.apiBase}/v0/users/-/collections/$subjectId',
        data: postData,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );
      return response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
    } catch (e) {
      debugPrint('[BangumiApi.updateCollection] Exception: $e');
    }
    return false;
  }

  static Future<bool> updateEpisodeStatus(
    int subjectId,
    String token,
    int epStatus,
  ) async {
    if (token.isEmpty) return false;
    try {
      final response = await _dio.post(
        '${_ApiConfig.apiBase}/subject/$subjectId/update/watched_eps',
        data: {'watched_eps': epStatus.toString()},
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      return response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
    } catch (e) {
      debugPrint('[BangumiApi.updateEpisodeStatus] Exception: $e');
    }
    return false;
  }

  static Future<List<Map<String, String>>> getSubjectComments(int id) async {
    final List<Map<String, String>>? cached = _commentsCache.get(id);
    if (cached != null) return cached;
    final List<Map<String, String>> comments = <Map<String, String>>[];

    for (final String base in _ApiConfig.htmlBases) {
      try {
        for (int page = 1; page <= 3; page++) {
          final String url = page == 1
              ? '$base/subject/$id/comments'
              : '$base/subject/$id/comments?page=$page';
          final dom.Document? document = await _getHtmlDocument(
            url,
            referer: '$base/subject/$id',
          );
          if (document == null) {
            break;
          }

          final List<Map<String, String>> pageComments =
              _parseSubjectCommentsDocument(document);

          if (pageComments.isEmpty) {
            break;
          }

          comments.addAll(pageComments);
          if (pageComments.length < 20) {
            break;
          }
        }

        if (comments.isEmpty) {
          final dom.Document? document = await _getHtmlDocument(
            '$base/subject/$id',
            referer: base,
          );
          if (document != null) {
            comments.addAll(_parseSubjectCommentsDocument(document));
          }
        }

        if (comments.isNotEmpty) {
          break;
        }
      } catch (e) {
        debugPrint('[BangumiApi.getSubjectComments] $base failed: $e');
      }
    }

    if (comments.isNotEmpty) {
      _commentsCache.set(id, comments);
    }
    return comments;
  }

  static Future<List<Map<String, String>>> getEpisodeComments(
    int episodeId,
  ) async {
    if (episodeId <= 0) {
      return <Map<String, String>>[];
    }
    final List<Map<String, String>>? cachedComments = _episodeCommentsCache.get(
      episodeId,
    );
    if (cachedComments != null) return cachedComments;

    final List<Map<String, String>> comments = <Map<String, String>>[];
    for (final String base in _ApiConfig.htmlBases) {
      try {
        final dom.Document? document = await _getHtmlDocument(
          '$base/ep/$episodeId',
          referer: base,
        );
        if (document == null) {
          continue;
        }
        final List<Map<String, String>> parsed = _parseEpisodeCommentsDocument(
          document,
        );
        if (parsed.isNotEmpty) {
          comments.addAll(parsed);
          break;
        }
      } catch (e) {
        debugPrint('[BangumiApi.getEpisodeComments] $base failed: $e');
      }
    }

    if (comments.isNotEmpty) {
      _episodeCommentsCache.set(episodeId, comments);
    }
    return comments;
  }

  static Future<List<dynamic>> getSubjectCharacters(int id) async {
    final List<dynamic>? cachedChars = _charactersCache.get(id);
    if (cachedChars != null) return cachedChars;
    try {
      final response = await _dio.get(
        '${_ApiConfig.apiBase}/v0/subjects/$id/characters',
      );
      if (response.statusCode == 200 && response.data is List) {
        _charactersCache.set(id, response.data);
        return _charactersCache.get(id)!;
      }
    } catch (e) {
      debugPrint('[BangumiApi.getSubjectCharacters] ${e.runtimeType}: $e');
    }
    return [];
  }

  static Future<List<dynamic>> getSubjectPersons(int id) async {
    final List<dynamic>? cachedPersons = _personsCache.get(id);
    if (cachedPersons != null) return cachedPersons;
    try {
      final response = await _dio.get(
        '${_ApiConfig.apiBase}/v0/subjects/$id/persons',
      );
      if (response.statusCode == 200 && response.data is List) {
        _personsCache.set(id, response.data);
        return _personsCache.get(id)!;
      }
    } catch (e) {
      debugPrint('[BangumiApi.getSubjectPersons] ${e.runtimeType}: $e');
    }
    return [];
  }

  static Future<List<dynamic>> getSubjectRelations(int id) async {
    final List<dynamic>? cachedRelations = _relationsCache.get(id);
    if (cachedRelations != null) return cachedRelations;
    try {
      final response = await _dio.get(
        '${_ApiConfig.apiBase}/v0/subjects/$id/subjects',
      );
      if (response.statusCode == 200 && response.data is List) {
        _relationsCache.set(id, response.data);
        return _relationsCache.get(id)!;
      }
    } catch (e) {
      debugPrint('[BangumiApi.getSubjectRelations] ${e.runtimeType}: $e');
    }
    return [];
  }
}

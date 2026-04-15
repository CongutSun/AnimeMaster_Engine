import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as parser;
import 'package:flutter/foundation.dart';
import 'dio_client.dart'; 

class _ApiConfig {
  static const String apiBase = 'https://api.bgm.tv';
  static const String webBase = 'https://bgm.tv';
  static const String chiiBase = 'https://chii.in';
}

class BangumiApi {
  static final Dio _dio = DioClient().dio;

  static final Map<int, Map<String, dynamic>> _animeDetailCache = {};
  static final Map<int, List<dynamic>> _charactersCache = {};
  static final Map<int, List<dynamic>> _personsCache = {};
  static final Map<int, List<dynamic>> _relationsCache = {};
  static final Map<int, List<Map<String, String>>> _commentsCache = {};

  static void _trimCache(Map cache, {int maxSize = 50}) {
    if (cache.length > maxSize) {
      final keysToRemove = cache.keys.take(cache.length - maxSize).toList();
      for (var key in keysToRemove) {
        cache.remove(key);
      }
    }
  }

  // 统一的 HTML 列表解析器，消除冗余代码
  static List<Map<String, dynamic>> _parseBrowserItemList(String html, int limit) {
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
          'images': {'large': imgUrl}
        });
      }
    }
    return results;
  }

  static Future<List<dynamic>> search(String keyword, {int type = 2, int start = 0, int maxResults = 25}) async {
    try {
      final response = await _dio.get(
        '${_ApiConfig.apiBase}/search/subject/${Uri.encodeComponent(keyword)}',
        queryParameters: {'type': type, 'start': start, 'max_results': maxResults},
      );
      if (response.statusCode == 200) return response.data['list'] ?? [];
    } catch (e) {
      debugPrint('[BangumiApi.search] Exception: $e');
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> getSubjectsByTag(String tag, {int type = 2, int page = 1}) async {
    try {
      final typeStr = type == 1 ? 'book' : 'anime';
      final response = await _dio.get(
        '${_ApiConfig.webBase}/$typeStr/tag/${Uri.encodeComponent(tag)}',
        queryParameters: {'page': page},
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode == 200) {
        return _parseBrowserItemList(utf8.decode(response.data), 24);
      }
    } catch (e) {
      debugPrint('[BangumiApi.getSubjectsByTag] Exception: $e');
    }
    return [];
  }

  static Future<List<dynamic>> getCharacterSubjects(int characterId) async {
    try {
      final response = await _dio.get('${_ApiConfig.apiBase}/v0/characters/$characterId/subjects');
      if (response.statusCode == 200) return response.data ?? [];
    } catch (e) {
      debugPrint('[BangumiApi.getCharacterSubjects] Exception: $e');
    }
    return [];
  }

  static Future<List<dynamic>> getPersonSubjects(int personId) async {
    try {
      final response = await _dio.get('${_ApiConfig.apiBase}/v0/persons/$personId/subjects');
      if (response.statusCode == 200) return response.data ?? [];
    } catch (e) {
      debugPrint('[BangumiApi.getPersonSubjects] Exception: $e');
    }
    return [];
  }

  static Future<List<dynamic>> getCalendar() async {
    try {
      final response = await _dio.get('${_ApiConfig.apiBase}/calendar');
      if (response.statusCode == 200 && response.data is List) return response.data;
    } catch (e) {
      debugPrint('[BangumiApi.getCalendar] Exception: $e');
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> getYearTop() async {
    final year = DateTime.now().year;
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
        return _parseBrowserItemList(utf8.decode(response.data), 10);
      }
    } catch (e) {
      debugPrint('[BangumiApi.getYearTop] Exception: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> getAnimeDetail(int id) async {
    if (_animeDetailCache.containsKey(id)) return _animeDetailCache[id]; 
    try {
      final response = await _dio.get('${_ApiConfig.apiBase}/v0/subjects/$id');
      if (response.statusCode == 200 && response.data is Map) {
        _animeDetailCache[id] = response.data;
        _trimCache(_animeDetailCache);
        return response.data;
      }
    } catch (e) {
      debugPrint('[BangumiApi.getAnimeDetail] Exception: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getUserCollection(int subjectId, String username, String token) async {
    if (username.isEmpty || token.isEmpty) return null;
    try {
      final response = await _dio.get(
        '${_ApiConfig.apiBase}/v0/users/$username/collections/$subjectId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200 && response.data is Map) return response.data;
    } catch (e) {
      debugPrint('[BangumiApi.getUserCollection] Exception: $e');
    }
    return null; 
  }

  static Future<List<dynamic>> getUserCollectionList(String username, {int type = 3, int subjectType = 2}) async {
    if (username.isEmpty) return [];
    try {
      final response = await _dio.get(
        '${_ApiConfig.apiBase}/v0/users/$username/collections',
        queryParameters: {'subject_type': subjectType, 'type': type, 'limit': 100},
      );
      if (response.statusCode == 200 && response.data is Map) {
        return response.data['data'] is List ? response.data['data'] : [];
      }
    } catch (e) {
      debugPrint('[BangumiApi.getUserCollectionList] Exception: $e');
    }
    return [];
  }

  static Future<bool> updateCollection(int subjectId, String token, Map<String, dynamic> postData) async {
    if (token.isEmpty) return false;
    try {
      final response = await _dio.post(
        '${_ApiConfig.apiBase}/v0/users/-/collections/$subjectId',
        data: postData, 
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'
        }),
      );
      return response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300;
    } catch (e) {
      debugPrint('[BangumiApi.updateCollection] Exception: $e');
    }
    return false;
  }

  static Future<bool> updateEpisodeStatus(int subjectId, String token, int epStatus) async {
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
      return response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300;
    } catch (e) {
      debugPrint('[BangumiApi.updateEpisodeStatus] Exception: $e');
    }
    return false;
  }

  static Future<List<Map<String, String>>> getSubjectComments(int id) async {
    if (_commentsCache.containsKey(id)) return _commentsCache[id]!;
    List<Map<String, String>> comments = [];

    try {
      final response = await _dio.get(
        '${_ApiConfig.chiiBase}/subject/$id',
        options: Options(responseType: ResponseType.bytes),
      );
      
      if (response.statusCode == 200) {
        final document = parser.parse(utf8.decode(response.data));
        final commentBox = document.getElementById('comment_box');
        
        if (commentBox != null) {
          for (var item in commentBox.getElementsByClassName('item')) {
            final author = item.querySelector('.text a')?.text.trim() ?? '网络用户';
            final content = item.querySelector('p')?.text.trim() ?? '';
            String rate = '未评级';
            
            final starSpan = item.querySelector('.text span.starlight');
            if (starSpan != null) {
              final match = RegExp(r'stars(\d+)').firstMatch(starSpan.attributes['class'] ?? '');
              if (match != null) rate = '${match.group(1)}分';
            }

            if (content.isNotEmpty) {
              comments.add({'author': author, 'rate': rate, 'content': content});
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[BangumiApi.getSubjectComments] Exception: $e');
    }
    
    if (comments.isNotEmpty) {
      _commentsCache[id] = comments;
      _trimCache(_commentsCache);
    }
    return comments;
  }

  static Future<List<dynamic>> getSubjectCharacters(int id) async {
    if (_charactersCache.containsKey(id)) return _charactersCache[id]!;
    try {
      final response = await _dio.get('${_ApiConfig.apiBase}/v0/subjects/$id/characters');
      if (response.statusCode == 200 && response.data is List) {
        _charactersCache[id] = response.data;
        _trimCache(_charactersCache);
        return _charactersCache[id]!;
      }
    } catch (e) {
      debugPrint('[BangumiApi.getSubjectCharacters] Exception: $e');
    }
    return [];
  }

  static Future<List<dynamic>> getSubjectPersons(int id) async {
    if (_personsCache.containsKey(id)) return _personsCache[id]!;
    try {
      final response = await _dio.get('${_ApiConfig.apiBase}/v0/subjects/$id/persons');
      if (response.statusCode == 200 && response.data is List) {
        _personsCache[id] = response.data;
        _trimCache(_personsCache);
        return _personsCache[id]!;
      }
    } catch (e) {
      debugPrint('[BangumiApi.getSubjectPersons] Exception: $e');
    }
    return [];
  }

  static Future<List<dynamic>> getSubjectRelations(int id) async {
    if (_relationsCache.containsKey(id)) return _relationsCache[id]!;
    try {
      final response = await _dio.get('${_ApiConfig.apiBase}/v0/subjects/$id/subjects');
      if (response.statusCode == 200 && response.data is List) {
        _relationsCache[id] = response.data;
        _trimCache(_relationsCache);
        return _relationsCache[id]!;
      }
    } catch (e) {
      debugPrint('[BangumiApi.getSubjectRelations] Exception: $e');
    }
    return [];
  }
}
import 'package:flutter/foundation.dart';

import '../api/bangumi_api.dart';
import '../models/anime.dart';

class SearchRepository {
  Future<List<Anime>> search({
    required String keyword,
    required int type,
    required int start,
    required int maxResults,
  }) async {
    final List<dynamic> rawResults = await BangumiApi.search(
      keyword,
      type: type,
      start: start,
      maxResults: maxResults,
    );
    if (rawResults.length < 40) {
      return _parseAnimeList(rawResults);
    }
    return compute(_parseAnimeList, rawResults);
  }
}

List<Anime> _parseAnimeList(List<dynamic> rawResults) {
  return rawResults
      .whereType<Map>()
      .map(
        (Map<dynamic, dynamic> item) =>
            Anime.fromJson(Map<String, dynamic>.from(item)),
      )
      .toList(growable: false);
}

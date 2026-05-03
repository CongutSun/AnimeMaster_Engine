/// Shared episode utilities used across detail_page, episode_watch_page,
/// torrent_media_resolver, and bangumi_api.
///
/// Extracted to eliminate ~200 lines of duplicated parsing logic.
library;

/// Extracts the episode number from a raw episode data map.
///
/// Prefers `'ep'` over `'sort'`, accepts [int], [num], or parseable [String].
int episodeNumber(Map<String, dynamic> episode) {
  final dynamic ep = episode['ep'] ?? episode['sort'];
  if (ep is int) return ep;
  if (ep is num) return ep.round();
  return int.tryParse(ep?.toString() ?? '') ?? 0;
}

/// Extracts the Bangumi episode id from a raw episode data map.
int episodeId(Map<String, dynamic> episode) {
  return int.tryParse(episode['id']?.toString() ?? '') ?? 0;
}

/// Returns the bare episode title (Chinese name preferred, falls back to
/// original name).
String episodePlainTitle(Map<String, dynamic> episode) {
  final String nameCn = episode['name_cn']?.toString().trim() ?? '';
  final String name = episode['name']?.toString().trim() ?? '';
  return nameCn.isNotEmpty ? nameCn : name;
}

/// Builds a human-readable episode title, stripping the redundant
/// "第N集" prefix when it duplicates the episode number.
String episodeTitle(Map<String, dynamic> episode) {
  final int number = episodeNumber(episode);
  final String title = stripRedundantEpisodePrefix(episodePlainTitle(episode), number);
  if (title.isEmpty) {
    return number > 0 ? '第$number集' : '未命名剧集';
  }
  return title;
}

/// Strips the redundant episode-number prefix (e.g. "第1集 标题" → "标题").
String stripRedundantEpisodePrefix(String title, int episodeNumber) {
  if (episodeNumber <= 0 || title.isEmpty) return title;
  final String padded = episodeNumber.toString().padLeft(2, '0');
  final List<RegExp> patterns = <RegExp>[
    RegExp('^第\\s*0?$episodeNumber\\s*[集话話]\\s*[:：.．、-]?\\s*'),
    RegExp('^0?$episodeNumber\\s*[:：.．、-]+\\s*'),
    RegExp('^0?$episodeNumber\\s+(?=\\D)'),
    RegExp('^$padded\\s*[:：.．、-]?\\s*'),
  ];
  for (final RegExp pattern in patterns) {
    final String stripped = title.replaceFirst(pattern, '').trim();
    if (stripped != title && stripped.isNotEmpty) return stripped;
  }
  return title;
}

/// Safe int conversion — handles [int], [num], and parseable [String].
int safeInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

/// Extracts the first numeric episode number from a free-text string.
///
/// Matches patterns like `S01E03`, `EP05`, `第7話`, or isolated `12`.
int? extractEpisodeNumber(String value) {
  final List<RegExp> patterns = <RegExp>[
    RegExp(r'\bS\d{1,2}E(\d{1,3})\b', caseSensitive: false),
    RegExp(r'\bEP?\s*\.?\s*(\d{1,3})\b', caseSensitive: false),
    RegExp(r'第\s*(\d{1,3})\s*[话話集回]'),
    RegExp(r'(?<!\d)(\d{1,3})(?!\d)'),
  ];

  for (final RegExp pattern in patterns) {
    final RegExpMatch? match = pattern.firstMatch(value);
    final int? number = int.tryParse(match?.group(1) ?? '');
    if (number != null && number > 0) return number;
  }
  return null;
}

/// Extracts aliases from a detail data map (cnName, originalName, infobox aliases).
List<String> extractAliases(
  String cnName,
  String originalName,
  Map<String, dynamic>? detailData,
) {
  final Set<String> aliases = <String>{
    if (cnName.isNotEmpty) cnName,
    if (originalName.isNotEmpty) originalName,
  };
  if (detailData != null && detailData!['infobox'] is List) {
    for (final Object? item in detailData!['infobox'] as List) {
      if (item is Map && item['key'] == '别名') {
        final Object? value = item['value'];
        if (value is List) {
          aliases.addAll(
            value.whereType<Map>().map((Map v) => v['v'].toString()),
          );
        } else if (value is String) {
          aliases.add(value);
        }
      }
    }
  }
  return aliases.where((String v) => v.trim().isNotEmpty).toList();
}

/// Returns the 'episode description' from a raw episode map.
String episodeDescription(Map<String, dynamic> episode) {
  return episode['desc']?.toString().trim() ?? '';
}

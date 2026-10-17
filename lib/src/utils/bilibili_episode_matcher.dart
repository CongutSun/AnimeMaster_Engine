import '../models/bilibili_video.dart';
import '../models/online_episode_source.dart';

class BilibiliEpisodeMatcher {
  static BilibiliPart? suggest(BilibiliVideo video, OnlineEpisodeQuery query) {
    if (query.episodeNumber <= 0) return null;
    final int? season = _season(query.subjectTitle);
    final candidates = video.parts.where((part) {
      final String title = part.title;
      if (RegExp(
        r'预告|片段|解说|混剪|特典|特别篇|OVA|\b(?:OP|ED|PV|MAD|AMV)\b',
        caseSensitive: false,
      ).hasMatch(title)) {
        return false;
      }
      final int? partSeason = _season(title) ?? _season(video.title);
      if (season != null && partSeason != null && season != partSeason) {
        return false;
      }
      return _episode(title) == query.episodeNumber;
    }).toList();
    return candidates.length == 1 ? candidates.single : null;
  }

  static int? _season(String title) {
    final match = RegExp(
      r'\bS(\d{1,2})(?:E\d|\b)',
      caseSensitive: false,
    ).firstMatch(title);
    if (match != null) return int.tryParse(match.group(1)!);
    final chinese = RegExp(r'第([\d一二三四五六七八九十百零〇两]+)季').firstMatch(title);
    return chinese == null ? null : _number(chinese.group(1)!);
  }

  static int? _episode(String title) {
    final season = RegExp(
      r'\bS\d{1,2}E(\d{1,3})(?!\d)',
      caseSensitive: false,
    ).firstMatch(title);
    if (season != null) return int.tryParse(season.group(1)!);
    final chinese = RegExp(
      r'第\s*([\d一二三四五六七八九十百零〇两]+)\s*[集话話回]',
    ).firstMatch(title);
    if (chinese != null) return _number(chinese.group(1)!);
    final ep = RegExp(
      r'\bEP?\s*(\d{1,3})(?!\d)',
      caseSensitive: false,
    ).firstMatch(title);
    if (ep != null) return int.tryParse(ep.group(1)!);
    if (RegExp(r'^\s*\d+\s*[-~至]\s*\d+').hasMatch(title)) return null;
    final prefix = RegExp(r'^\s*(\d{1,3})(?:\s|[.、:：_-]|$)').firstMatch(title);
    return prefix == null ? null : int.tryParse(prefix.group(1)!);
  }

  static int? _number(String text) {
    final int? numeric = int.tryParse(text);
    if (numeric != null) return numeric;
    const digits = <String, int>{
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    int result = 0;
    int current = 0;
    for (final String char in text.split('')) {
      if (digits.containsKey(char)) {
        current = digits[char]!;
      } else if (char == '十' || char == '百') {
        result += (current == 0 ? 1 : current) * (char == '十' ? 10 : 100);
        current = 0;
      } else {
        return null;
      }
    }
    return result + current;
  }
}

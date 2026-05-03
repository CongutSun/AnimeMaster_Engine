import 'package:flutter/foundation.dart';

class TaskTitleParseResult {
  final String title;
  final String cleanedTitle;
  final String episodeLabel;
  final int? episodeNumber;

  const TaskTitleParseResult({
    required this.title,
    required this.cleanedTitle,
    required this.episodeLabel,
    required this.episodeNumber,
  });
}

class TaskTitleParser {
  static const int isolateThresholdBytes = 100 * 1024;

  static String stripSourcePrefix(String title) {
    return title.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '').trim();
  }

  static String extractEpisodeLabel(String title) {
    final String normalized = stripSourcePrefix(title);
    if (normalized.isEmpty) {
      return '';
    }

    final List<RegExp> patterns = <RegExp>[
      RegExp(r'(第\s*\d+\s*[话話集回])', caseSensitive: false),
      RegExp(r'\b(S\d{1,2}E\d{1,3})\b', caseSensitive: false),
      RegExp(r'\b(EP?\s*\d{1,3}(?:\.\d+)?)\b', caseSensitive: false),
    ];

    for (final RegExp pattern in patterns) {
      final Match? match = pattern.firstMatch(normalized);
      if (match != null) {
        return match.group(1)?.trim() ?? '';
      }
    }

    return '';
  }

  static int? extractEpisodeNumber(String title) {
    final String normalized = stripSourcePrefix(title);
    final List<RegExp> patterns = <RegExp>[
      RegExp(r'\bS\d{1,2}E(\d{1,3})\b', caseSensitive: false),
      RegExp(r'\bEP?\s*\.?\s*(\d{1,3})\b', caseSensitive: false),
      RegExp(r'第\s*(\d{1,3})\s*[话話集回]'),
      RegExp(r'(?<!\d)(\d{1,3})(?!\d)'),
    ];

    for (final RegExp pattern in patterns) {
      final RegExpMatch? match = pattern.firstMatch(normalized);
      final int? number = int.tryParse(match?.group(1) ?? '');
      if (number != null && number > 0) {
        return number;
      }
    }
    return null;
  }

  static String buildEpisodeDisplayLabel({
    required int episodeNumber,
    String episodeTitle = '',
  }) {
    final String trimmedTitle = episodeTitle.trim();
    if (episodeNumber <= 0) {
      return trimmedTitle;
    }
    if (trimmedTitle.isEmpty) {
      return '第 $episodeNumber 集';
    }
    return '第 $episodeNumber 集 · $trimmedTitle';
  }

  static TaskTitleParseResult parse(String title) {
    return TaskTitleParseResult(
      title: title,
      cleanedTitle: stripSourcePrefix(title),
      episodeLabel: extractEpisodeLabel(title),
      episodeNumber: extractEpisodeNumber(title),
    );
  }

  static Future<List<TaskTitleParseResult>> parseBatch(
    List<String> titles,
  ) async {
    final int payloadBytes = titles.fold<int>(
      0,
      (int total, String title) => total + title.length * 2,
    );
    if (payloadBytes < isolateThresholdBytes) {
      return _parseBatchSync(titles);
    }
    return compute(_parseBatchSync, titles);
  }
}

List<TaskTitleParseResult> _parseBatchSync(List<String> titles) {
  return titles.map(TaskTitleParser.parse).toList(growable: false);
}

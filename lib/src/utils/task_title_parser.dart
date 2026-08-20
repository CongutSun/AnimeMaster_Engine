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

  /// Returns whether a release title explicitly identifies one episode.
  /// Resolution, year and codec numbers are deliberately ignored so a search
  /// for episode 10 does not accidentally match "10bit" or "1080p".
  static bool matchesEpisodeNumber(String title, int episodeNumber) {
    if (episodeNumber <= 0) {
      return true;
    }
    final String normalized = stripSourcePrefix(title);
    if (normalized.isEmpty) {
      return false;
    }

    final RegExpMatch? range = RegExp(
      r'(?<!\d)0*(\d{1,3})\s*[-~～]\s*0*(\d{1,3})(?!\d)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (range != null) {
      final int? start = int.tryParse(range.group(1) ?? '');
      final int? end = int.tryParse(range.group(2) ?? '');
      if (start != null && end != null && start != end) {
        return false;
      }
    }

    final List<RegExp> patterns = <RegExp>[
      RegExp(r'\bS\d{1,2}E0*(\d{1,4})(?:v\d+)?\b', caseSensitive: false),
      RegExp(
        r'\b(?:EP?|Episode)\s*[._-]?\s*0*(\d{1,4})(?:v\d+)?\b',
        caseSensitive: false,
      ),
      RegExp(r'第\s*0*(\d{1,4})\s*[话話集回]'),
      RegExp(r'[\[【]\s*0*(\d{1,3})(?:v\d+)?\s*[\]】]'),
      RegExp(
        r'(?:\s|^)[-–—]\s*0*(\d{1,3})(?:v\d+)?(?=\s*(?:[\[({]|\.(?:mkv|mp4)|$))',
        caseSensitive: false,
      ),
      RegExp(
        r'(?<!\d)0*(\d{1,3})(?:v\d+)?(?=\s*(?:[\[({]|END\b|\.(?:mkv|mp4)|$))',
        caseSensitive: false,
      ),
    ];

    for (final RegExp pattern in patterns) {
      for (final RegExpMatch match in pattern.allMatches(normalized)) {
        if (int.tryParse(match.group(1) ?? '') == episodeNumber) {
          return true;
        }
      }
    }
    return false;
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

class TaskTitleParser {
  static String stripSourcePrefix(String title) {
    return title.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '').trim();
  }

  static String extractEpisodeLabel(String title) {
    final String normalized = stripSourcePrefix(title);
    if (normalized.isEmpty) {
      return '';
    }

    final List<RegExp> patterns = <RegExp>[
      RegExp(r'(第\s*\d+\s*[话話集])', caseSensitive: false),
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
}

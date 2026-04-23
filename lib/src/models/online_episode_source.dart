class OnlineEpisodeQuery {
  final int bangumiSubjectId;
  final int bangumiEpisodeId;
  final String subjectTitle;
  final List<String> aliases;
  final int episodeNumber;
  final String episodeTitle;

  const OnlineEpisodeQuery({
    required this.bangumiSubjectId,
    required this.bangumiEpisodeId,
    required this.subjectTitle,
    required this.aliases,
    required this.episodeNumber,
    required this.episodeTitle,
  });

  String get episodeLabel {
    if (episodeNumber <= 0) {
      return episodeTitle.trim();
    }
    final String title = _stripRedundantEpisodePrefix(
      episodeTitle.trim(),
      episodeNumber,
    );
    return title.isEmpty ? '第$episodeNumber集' : '第$episodeNumber集 · $title';
  }
}

String _stripRedundantEpisodePrefix(String title, int episodeNumber) {
  if (episodeNumber <= 0 || title.isEmpty) {
    return title;
  }
  final String padded = episodeNumber.toString().padLeft(2, '0');
  final List<RegExp> patterns = <RegExp>[
    RegExp('^第\\s*0?$episodeNumber\\s*[集话話]\\s*[:：.．、-]?\\s*'),
    RegExp('^0?$episodeNumber\\s*[:：.．、-]+\\s*'),
    RegExp('^0?$episodeNumber\\s+(?=\\D)'),
    RegExp('^$padded\\s*[:：.．、-]?\\s*'),
  ];
  for (final RegExp pattern in patterns) {
    final String stripped = title.replaceFirst(pattern, '').trim();
    if (stripped != title && stripped.isNotEmpty) {
      return stripped;
    }
  }
  return title;
}

class OnlineEpisodeSourceResult {
  final String title;
  final String pageUrl;
  final String mediaUrl;
  final String sourceName;
  final String snippet;
  final Map<String, String> headers;
  final int score;
  final bool verified;

  const OnlineEpisodeSourceResult({
    required this.title,
    required this.pageUrl,
    required this.mediaUrl,
    required this.sourceName,
    required this.snippet,
    this.headers = const <String, String>{},
    required this.score,
    this.verified = false,
  });

  String get host =>
      Uri.tryParse(mediaUrl)?.host ?? Uri.tryParse(pageUrl)?.host ?? '';
}

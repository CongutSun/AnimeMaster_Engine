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
    final String title = episodeTitle.trim();
    return title.isEmpty ? '第$episodeNumber 集' : '第$episodeNumber 集 · $title';
  }
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

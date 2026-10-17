import '../utils/episode_helpers.dart';

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
    final String title = stripRedundantEpisodePrefix(
      episodeTitle.trim(),
      episodeNumber,
    );
    return title.isEmpty ? '第$episodeNumber集' : '第$episodeNumber集 · $title';
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
  final String? bilibiliBvid;

  const OnlineEpisodeSourceResult({
    required this.title,
    required this.pageUrl,
    required this.mediaUrl,
    required this.sourceName,
    required this.snippet,
    this.headers = const <String, String>{},
    required this.score,
    this.verified = false,
    this.bilibiliBvid,
  });

  String get host {
    final String? mediaHost = Uri.tryParse(mediaUrl)?.host;
    return mediaHost != null && mediaHost.isNotEmpty
        ? mediaHost
        : Uri.tryParse(pageUrl)?.host ?? '';
  }

  bool get canAutoPlay => bilibiliBvid == null && mediaUrl.trim().isNotEmpty;
}

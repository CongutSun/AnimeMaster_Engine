import 'online_episode_source.dart';

class PlayableMedia {
  final String title;
  final String url;
  final Map<String, String>? headers;
  final bool isLocal;
  final String localFilePath;
  final String subjectTitle;
  final String episodeLabel;
  final int bangumiSubjectId;
  final int bangumiEpisodeId;
  final OnlineEpisodeQuery? onlineQuery;
  final List<OnlineEpisodeQuery> onlineEpisodes;
  final List<OnlineEpisodeSourceResult> onlineSources;

  PlayableMedia({
    required this.title,
    required this.url,
    this.headers,
    this.isLocal = false,
    this.localFilePath = '',
    this.subjectTitle = '',
    this.episodeLabel = '',
    this.bangumiSubjectId = 0,
    this.bangumiEpisodeId = 0,
    this.onlineQuery,
    this.onlineEpisodes = const <OnlineEpisodeQuery>[],
    this.onlineSources = const <OnlineEpisodeSourceResult>[],
  });

  bool get hasOnlineContext =>
      onlineQuery != null ||
      onlineEpisodes.isNotEmpty ||
      onlineSources.isNotEmpty;
}

abstract class MediaResolver {
  bool canResolve(dynamic sourceData);

  Future<PlayableMedia> resolve(dynamic sourceData);
}

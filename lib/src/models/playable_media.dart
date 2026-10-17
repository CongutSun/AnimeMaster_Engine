import 'online_episode_source.dart';
import 'bilibili_video.dart';

class PlayableMedia {
  final String title;
  final String url;
  final String? audioUrl;
  final BilibiliPlayback? bilibili;
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
    this.audioUrl,
    this.bilibili,
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

  PlayableMedia withEpisodeContext({
    required String subjectTitle,
    required String episodeLabel,
    required int bangumiSubjectId,
    required int bangumiEpisodeId,
  }) => PlayableMedia(
    title: title,
    url: url,
    audioUrl: audioUrl,
    bilibili: bilibili,
    headers: headers,
    isLocal: isLocal,
    localFilePath: localFilePath,
    subjectTitle: subjectTitle,
    episodeLabel: episodeLabel,
    bangumiSubjectId: bangumiSubjectId,
    bangumiEpisodeId: bangumiEpisodeId,
    onlineQuery: onlineQuery,
    onlineEpisodes: onlineEpisodes,
    onlineSources: onlineSources,
  );
}

abstract class MediaResolver {
  bool canResolve(dynamic sourceData);

  Future<PlayableMedia> resolve(dynamic sourceData);
}

class PlayableMedia {
  final String title;
  final String url;
  final Map<String, String>? headers;
  final bool isLocal;
  final String localFilePath;
  final String subjectTitle;
  final String episodeLabel;

  PlayableMedia({
    required this.title,
    required this.url,
    this.headers,
    this.isLocal = false,
    this.localFilePath = '',
    this.subjectTitle = '',
    this.episodeLabel = '',
  });
}

abstract class MediaResolver {
  bool canResolve(dynamic sourceData);

  Future<PlayableMedia> resolve(dynamic sourceData);
}

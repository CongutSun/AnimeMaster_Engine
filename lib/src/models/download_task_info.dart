class DownloadTaskInfo {
  final String hash;
  final String title;
  final String url;
  final String savePath;
  final String targetPath;
  final String subjectTitle;
  final String episodeLabel;
  final int bangumiSubjectId;
  final int bangumiEpisodeId;
  bool isCompleted;

  DownloadTaskInfo({
    required this.hash,
    required this.title,
    required this.url,
    required this.savePath,
    required this.targetPath,
    this.subjectTitle = '',
    this.episodeLabel = '',
    this.bangumiSubjectId = 0,
    this.bangumiEpisodeId = 0,
    this.isCompleted = false,
  });

  factory DownloadTaskInfo.fromJson(Map<String, dynamic> json) {
    return DownloadTaskInfo(
      hash: json['hash'],
      title: json['title'],
      url: json['url'],
      savePath: json['savePath'],
      targetPath: json['targetPath'] ?? '',
      subjectTitle: json['subjectTitle'] ?? '',
      episodeLabel: json['episodeLabel'] ?? '',
      bangumiSubjectId:
          int.tryParse(json['bangumiSubjectId']?.toString() ?? '') ?? 0,
      bangumiEpisodeId:
          int.tryParse(json['bangumiEpisodeId']?.toString() ?? '') ?? 0,
      isCompleted: json['isCompleted'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'hash': hash,
    'title': title,
    'url': url,
    'savePath': savePath,
    'targetPath': targetPath,
    'subjectTitle': subjectTitle,
    'episodeLabel': episodeLabel,
    'bangumiSubjectId': bangumiSubjectId,
    'bangumiEpisodeId': bangumiEpisodeId,
    'isCompleted': isCompleted,
  };

  String get displayTitle => title.trim().isEmpty ? hash : title.trim();

  String get displaySubtitle {
    final List<String> parts = <String>[
      if (subjectTitle.trim().isNotEmpty) subjectTitle.trim(),
      if (episodeLabel.trim().isNotEmpty) episodeLabel.trim(),
    ];
    return parts.join('  ·  ');
  }

  DownloadTaskInfo copyWith({
    String? hash,
    String? title,
    String? url,
    String? savePath,
    String? targetPath,
    String? subjectTitle,
    String? episodeLabel,
    int? bangumiSubjectId,
    int? bangumiEpisodeId,
    bool? isCompleted,
  }) {
    return DownloadTaskInfo(
      hash: hash ?? this.hash,
      title: title ?? this.title,
      url: url ?? this.url,
      savePath: savePath ?? this.savePath,
      targetPath: targetPath ?? this.targetPath,
      subjectTitle: subjectTitle ?? this.subjectTitle,
      episodeLabel: episodeLabel ?? this.episodeLabel,
      bangumiSubjectId: bangumiSubjectId ?? this.bangumiSubjectId,
      bangumiEpisodeId: bangumiEpisodeId ?? this.bangumiEpisodeId,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

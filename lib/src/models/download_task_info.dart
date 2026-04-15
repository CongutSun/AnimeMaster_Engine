class DownloadTaskInfo {
  final String hash;
  final String title;
  final String url;
  final String savePath;
  final String targetPath;
  final String subjectTitle;
  final String episodeLabel;
  bool isCompleted;

  DownloadTaskInfo({
    required this.hash,
    required this.title,
    required this.url,
    required this.savePath,
    required this.targetPath,
    this.subjectTitle = '',
    this.episodeLabel = '',
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
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

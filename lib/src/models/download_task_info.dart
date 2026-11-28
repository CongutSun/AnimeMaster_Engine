import 'dart:io';
import 'cache_episode_file.dart';

class DownloadTaskInfo {
  final String hash;
  final String title;
  final String url;
  final String savePath;
  final String targetPath;
  final int targetSize;
  final int audioSize;
  final String subjectTitle;
  final String episodeLabel;
  final int bangumiSubjectId;
  final int bangumiEpisodeId;
  final List<CacheEpisodeFile> files;
  bool isCompleted;
  bool isPaused;

  DownloadTaskInfo({
    required this.hash,
    required this.title,
    required this.url,
    required this.savePath,
    required this.targetPath,
    this.targetSize = 0,
    this.audioSize = 0,
    this.files = const [],
    this.subjectTitle = '',
    this.episodeLabel = '',
    this.bangumiSubjectId = 0,
    this.bangumiEpisodeId = 0,
    this.isCompleted = false,
    this.isPaused = false,
  });

  factory DownloadTaskInfo.fromJson(Map<String, dynamic> json) {
    return DownloadTaskInfo(
      files: [
        for (final e in json['episodeFiles'] ?? [])
          CacheEpisodeFile.fromJson(Map<String, dynamic>.from(e)),
      ],
      hash: json['hash'],
      title: json['title'],
      url: json['url'],
      savePath: json['savePath'],
      targetPath: json['targetPath'] ?? '',
      targetSize: int.tryParse(json['targetSize']?.toString() ?? '') ?? 0,
      audioSize: int.tryParse(json['audioSize']?.toString() ?? '') ?? 0,
      subjectTitle: json['subjectTitle'] ?? '',
      episodeLabel: json['episodeLabel'] ?? '',
      bangumiSubjectId:
          int.tryParse(json['bangumiSubjectId']?.toString() ?? '') ?? 0,
      bangumiEpisodeId:
          int.tryParse(json['bangumiEpisodeId']?.toString() ?? '') ?? 0,
      isCompleted: json['isCompleted'] ?? false,
      isPaused: json['isPaused'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'episodeFiles': files.map((f) => f.toJson()).toList(),
    'hash': hash,
    'title': title,
    'url': url,
    'savePath': savePath,
    'targetPath': targetPath,
    'targetSize': targetSize,
    'audioSize': audioSize,
    'subjectTitle': subjectTitle,
    'episodeLabel': episodeLabel,
    'bangumiSubjectId': bangumiSubjectId,
    'bangumiEpisodeId': bangumiEpisodeId,
    'isCompleted': isCompleted,
    'isPaused': isPaused,
  };

  String get displayTitle => title.trim().isEmpty ? hash : title.trim();

  static final bilibiliKey = RegExp(
    r'^bili_(BV[0-9A-Za-z]{10})_([1-9][0-9]*)$',
  );
  bool get isBilibili => bilibiliKey.hasMatch(hash);
  String? get bilibiliIdentity {
    final match = bilibiliKey.firstMatch(hash);
    return match == null ? null : 'bilibili:${match[1]}:${match[2]}';
  }

  String? get localAudioUrl =>
      audioSize > 0 ? File('$savePath/audio.m4a').uri.toString() : null;

  Future<bool> hasCompleteFile() async {
    if (!isCompleted || targetPath.isEmpty) return false;
    final stat = await FileStat.stat(targetPath);
    final videoReady =
        stat.type == FileSystemEntityType.file &&
        stat.size > 0 &&
        (targetSize <= 0 || stat.size == targetSize);
    if (!videoReady || audioSize == 0) return videoReady;
    final audio = await FileStat.stat('$savePath/audio.m4a');
    return audio.type == FileSystemEntityType.file && audio.size == audioSize;
  }

  String get displaySubtitle {
    final List<String> parts = <String>[
      if (subjectTitle.trim().isNotEmpty) subjectTitle.trim(),
      if (episodeLabel.trim().isNotEmpty) episodeLabel.trim(),
    ];
    return parts.join('  ·  ');
  }

  DownloadTaskInfo forFile(CacheEpisodeFile f, {bool single = false}) =>
      copyWith(
        files: single ? [f] : files,
        targetPath: f.path,
        targetSize: f.size > 0 || targetPath != f.path ? f.size : targetSize,
        episodeLabel: f.label,
        bangumiEpisodeId: f.episodeId,
      );
  Iterable<DownloadTaskInfo> get playableFiles =>
      files.isEmpty ? [this] : files.map((file) => forFile(file, single: true));
  DownloadTaskInfo copyWith({
    List<CacheEpisodeFile>? files,
    String? hash,
    String? title,
    String? url,
    String? savePath,
    String? targetPath,
    int? targetSize,
    int? audioSize,
    String? subjectTitle,
    String? episodeLabel,
    int? bangumiSubjectId,
    int? bangumiEpisodeId,
    bool? isCompleted,
    bool? isPaused,
  }) {
    return DownloadTaskInfo(
      files: files ?? this.files,
      hash: hash ?? this.hash,
      title: title ?? this.title,
      url: url ?? this.url,
      savePath: savePath ?? this.savePath,
      targetPath: targetPath ?? this.targetPath,
      targetSize: targetSize ?? this.targetSize,
      audioSize: audioSize ?? this.audioSize,
      subjectTitle: subjectTitle ?? this.subjectTitle,
      episodeLabel: episodeLabel ?? this.episodeLabel,
      bangumiSubjectId: bangumiSubjectId ?? this.bangumiSubjectId,
      bangumiEpisodeId: bangumiEpisodeId ?? this.bangumiEpisodeId,
      isCompleted: isCompleted ?? this.isCompleted,
      isPaused: isPaused ?? this.isPaused,
    );
  }
}

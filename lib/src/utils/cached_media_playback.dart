import '../managers/download_manager.dart';
import '../models/download_task_info.dart';
import '../models/online_episode_source.dart';
import '../models/playable_media.dart';
import 'task_title_parser.dart';
import 'torrent_stream_server.dart';

class CachedPlaybackSession {
  final PlayableMedia media;
  final TorrentStreamServer? streamServer;

  const CachedPlaybackSession({required this.media, this.streamServer});
}

class CachedMediaPlayback {
  static final _fileOpenError = RegExp(
    r'failed to open|cannot open|could not open|unrecognized file format|no video or audio streams',
    caseSensitive: false,
  );

  static bool isFileOpenError(String message) =>
      _fileOpenError.hasMatch(message);

  static List<DownloadTaskInfo> episodeTasks(
    Iterable<DownloadTaskInfo> tasks,
    OnlineEpisodeQuery query, {
    String previousPath = '',
  }) {
    final names = {
      query.subjectTitle,
      ...query.aliases,
    }.map((name) => name.trim().toLowerCase()).where((name) => name.isNotEmpty);
    final matches = tasks.expand((task) => task.playableFiles).where((task) {
      if (task.bangumiSubjectId > 0 &&
          task.bangumiSubjectId != query.bangumiSubjectId) {
        return false;
      }
      if (task.bangumiEpisodeId > 0 && query.bangumiEpisodeId > 0) {
        return task.bangumiEpisodeId == query.bangumiEpisodeId;
      }
      if (task.files.isEmpty &&
          previousPath.isNotEmpty &&
          task.targetPath == previousPath) {
        return true;
      }
      if (query.episodeNumber <= 0) return false;
      if (task.bangumiSubjectId == 0) {
        final text = '${task.subjectTitle} ${task.title} ${task.targetPath}'
            .toLowerCase();
        if (!names.any(text.contains)) return false;
      }
      if (task.files.isNotEmpty) {
        return task.files.any(
          (f) => f.path == task.targetPath && f.number == query.episodeNumber,
        );
      }
      return TaskTitleParser.extractEpisodeNumber(
            '${task.episodeLabel} ${task.title} ${task.targetPath}',
          ) ==
          query.episodeNumber;
    }).toList();
    int score(DownloadTaskInfo task) =>
        (previousPath.isNotEmpty && task.targetPath == previousPath ? 200 : 0) +
        (query.bangumiEpisodeId > 0 &&
                task.bangumiEpisodeId == query.bangumiEpisodeId
            ? 100
            : 0) +
        (task.bangumiSubjectId == query.bangumiSubjectId ? 60 : 0) +
        (task.isCompleted ? 20 : 0) +
        (task.targetSize > 0 ? 10 : 0);
    return matches..sort((a, b) => score(b).compareTo(score(a)));
  }

  static Future<DownloadTaskInfo?> preferredTask(
    Iterable<DownloadTaskInfo> candidates,
  ) async {
    DownloadTaskInfo? partial;
    for (final task in candidates) {
      if (await task.hasCompleteFile()) return task;
      if (!task.isCompleted && !task.isBilibili) partial ??= task;
    }
    return partial;
  }

  static Future<CachedPlaybackSession> prepare(DownloadTaskInfo task) async {
    await DownloadManager().prepareForPlayback(task.hash);

    if (task.isCompleted) {
      if (!await task.hasCompleteFile()) {
        throw StateError('缓存文件已丢失或不完整，请重新下载');
      }
      return CachedPlaybackSession(
        media: PlayableMedia(
          title: task.displayTitle,
          url: task.targetPath,
          audioUrl: task.localAudioUrl,
          bilibiliCacheIdentity: task.bilibiliIdentity,
          isLocal: true,
          localFilePath: task.targetPath,
          subjectTitle: task.subjectTitle,
          episodeLabel: task.episodeLabel,
          bangumiSubjectId: task.bangumiSubjectId,
          bangumiEpisodeId: task.bangumiEpisodeId,
        ),
      );
    }

    if (task.isBilibili) throw StateError('请先完成这个分 P 的离线缓存');
    if (task.targetSize > 0) {
      DownloadManager().prioritizePlaybackRange(
        task.hash,
        task.targetPath,
        0,
        512 * 1024,
      );
      final TorrentStreamServer streamServer = TorrentStreamServer(
        videoFilePath: task.targetPath,
        videoSize: task.targetSize,
        infoHash: task.hash,
      );
      final String streamUrl = await streamServer.start();
      return CachedPlaybackSession(
        media: PlayableMedia(
          title: task.displayTitle,
          url: streamUrl,
          localFilePath: task.targetPath,
          subjectTitle: task.subjectTitle,
          episodeLabel: task.episodeLabel,
          bangumiSubjectId: task.bangumiSubjectId,
          bangumiEpisodeId: task.bangumiEpisodeId,
        ),
        streamServer: streamServer,
      );
    }

    return CachedPlaybackSession(
      media: PlayableMedia(
        title: task.displayTitle,
        url: task.url,
        localFilePath: task.targetPath,
        subjectTitle: task.subjectTitle,
        episodeLabel: task.episodeLabel,
        bangumiSubjectId: task.bangumiSubjectId,
        bangumiEpisodeId: task.bangumiEpisodeId,
      ),
    );
  }
}

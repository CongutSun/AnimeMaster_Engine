import 'dart:io';

import '../managers/download_manager.dart';
import '../models/download_task_info.dart';
import '../models/playable_media.dart';
import 'torrent_stream_server.dart';

class CachedPlaybackSession {
  final PlayableMedia media;
  final TorrentStreamServer? streamServer;

  const CachedPlaybackSession({required this.media, this.streamServer});
}

class CachedMediaPlayback {
  static Future<CachedPlaybackSession> prepare(DownloadTaskInfo task) async {
    await DownloadManager().prepareForPlayback(task.hash);

    final File localFile = File(task.targetPath);
    final bool canUseLocalFile = task.isCompleted && localFile.existsSync();
    if (canUseLocalFile) {
      return CachedPlaybackSession(
        media: PlayableMedia(
          title: task.displayTitle,
          url: task.targetPath,
          isLocal: true,
          localFilePath: task.targetPath,
          subjectTitle: task.subjectTitle,
          episodeLabel: task.episodeLabel,
          bangumiSubjectId: task.bangumiSubjectId,
          bangumiEpisodeId: task.bangumiEpisodeId,
        ),
      );
    }

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

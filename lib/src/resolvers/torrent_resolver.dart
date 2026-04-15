import 'dart:async';

import '../coordinator/torrent_media_resolver.dart';
import '../managers/download_manager.dart';
import '../models/playable_media.dart';
import '../utils/torrent_stream_server.dart';

class TorrentResolver {
  TorrentStreamServer? _streamServer;

  Future<PlayableMedia> resolve(
    String urlOrMagnet,
    String title,
    Function(double) onProgress,
  ) async {
    final ResolvedMediaInfo mediaInfo = await TorrentMediaResolver()
        .resolveAndPrepare(urlOrMagnet);
    final Completer<PlayableMedia> completer = Completer<PlayableMedia>();

    Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      final double progress =
          DownloadManager().getProgress(mediaInfo.infoHash) * 100;
      onProgress(progress);

      if (progress >= 3.0 || progress == 100.0) {
        _streamServer?.stop();
        _streamServer = TorrentStreamServer(
          videoFilePath: mediaInfo.filePath,
          videoSize: mediaInfo.fileSize,
          infoHash: mediaInfo.infoHash,
        );

        final String streamUrl = await _streamServer!.start();
        if (!completer.isCompleted) {
          completer.complete(
            PlayableMedia(
              url: streamUrl,
              title: title.isEmpty ? mediaInfo.title : title,
            ),
          );
        }
        timer.cancel();
      }
    });

    return completer.future;
  }

  void dispose() {
    _streamServer?.stop();
  }
}

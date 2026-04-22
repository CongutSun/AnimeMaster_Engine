import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../coordinator/torrent_media_resolver.dart';
import '../managers/download_manager.dart';
import '../models/download_task_info.dart';
import '../models/playable_media.dart';
import '../screens/video_player_page.dart';
import 'torrent_stream_server.dart';

class MagnetActionHelper {
  static const double _playbackBufferThreshold = 0.03;
  static const int _startupProbeBytes = 512 * 1024;

  static Future<void> process(
    BuildContext context,
    String rawSource, {
    required bool autoPlay,
    String preferredTitle = '',
    String subjectTitle = '',
    String episodeLabel = '',
    int bangumiSubjectId = 0,
    int bangumiEpisodeId = 0,
  }) async {
    bool loadingDialogOpen = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.blueAccent,
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    autoPlay ? '正在准备任务并建立播放链路...' : '正在解析资源并创建下载任务...',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    loadingDialogOpen = true;

    void closeLoadingDialog() {
      if (!loadingDialogOpen || !context.mounted) {
        return;
      }

      final NavigatorState navigator = Navigator.of(
        context,
        rootNavigator: true,
      );
      if (navigator.canPop()) {
        navigator.pop();
      }
      loadingDialogOpen = false;
    }

    try {
      final TorrentMediaResolver resolver = TorrentMediaResolver();
      final PreparedTorrentTask preparedTask = await resolver.prepareTask(
        rawSource,
        preferredTitle: preferredTitle,
        subjectTitle: subjectTitle,
        episodeLabel: episodeLabel,
        bangumiSubjectId: bangumiSubjectId,
        bangumiEpisodeId: bangumiEpisodeId,
      );

      await DownloadManager().addTask(
        preparedTask.taskInfo,
        preparedTask.torrentBytes,
        streamOptimized: autoPlay,
      );

      closeLoadingDialog();
      if (!context.mounted) {
        return;
      }

      if (autoPlay) {
        await _openPreparedPlayback(context, preparedTask.taskInfo);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('任务已加入缓存中心。'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      closeLoadingDialog();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('解析异常：${_friendlyErrorText(error)}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  static String _friendlyErrorText(Object error) {
    final String message = error
        .toString()
        .replaceFirst('Exception: ', '')
        .trim();
    return message.isEmpty ? '未知错误' : message;
  }

  static Future<void> _openPreparedPlayback(
    BuildContext context,
    DownloadTaskInfo config,
  ) async {
    await DownloadManager().prepareForPlayback(config.hash);
    DownloadManager().prioritizePlaybackRange(
      config.hash,
      config.targetPath,
      0,
      _startupProbeBytes,
    );

    final double progress = DownloadManager().getProgress(config.hash);
    final bool startupReady = await DownloadManager().isRangeReadable(
      config.hash,
      config.targetPath,
      bytes: _startupProbeBytes,
    );
    if (!context.mounted) {
      return;
    }
    if (!startupReady && progress < 1.0) {
      final bool shouldPlay =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _WaitProgressDialog(
              config: config,
              threshold: _playbackBufferThreshold,
            ),
          ) ??
          false;
      if (!shouldPlay || !context.mounted) {
        return;
      }
    }

    final double latestProgress = DownloadManager().getProgress(config.hash);
    final File localFile = File(config.targetPath);
    final bool canUseLocalFile =
        latestProgress >= 1.0 && await localFile.exists();
    TorrentStreamServer? streamServer;
    final int targetSize = config.targetSize > 0
        ? config.targetSize
        : (await localFile.exists() ? await localFile.length() : 0);
    final PlayableMedia media;
    if (canUseLocalFile) {
      media = PlayableMedia(
        title: config.displayTitle,
        url: config.targetPath,
        isLocal: true,
        localFilePath: config.targetPath,
        subjectTitle: config.subjectTitle,
        episodeLabel: config.episodeLabel,
        bangumiSubjectId: config.bangumiSubjectId,
        bangumiEpisodeId: config.bangumiEpisodeId,
      );
    } else if (targetSize > 0) {
      streamServer = TorrentStreamServer(
        videoFilePath: config.targetPath,
        videoSize: targetSize,
        infoHash: config.hash,
      );
      final String streamUrl = await streamServer.start();
      media = PlayableMedia(
        title: config.displayTitle,
        url: streamUrl,
        localFilePath: config.targetPath,
        subjectTitle: config.subjectTitle,
        episodeLabel: config.episodeLabel,
        bangumiSubjectId: config.bangumiSubjectId,
        bangumiEpisodeId: config.bangumiEpisodeId,
      );
    } else {
      media = PlayableMedia(
        title: config.displayTitle,
        url: config.url,
        localFilePath: config.targetPath,
        subjectTitle: config.subjectTitle,
        episodeLabel: config.episodeLabel,
        bangumiSubjectId: config.bangumiSubjectId,
        bangumiEpisodeId: config.bangumiEpisodeId,
      );
    }

    if (!context.mounted) {
      streamServer?.stop();
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (BuildContext context) =>
            VideoPlayerPage(media: media, streamServer: streamServer),
      ),
    );
  }
}

class _WaitProgressDialog extends StatefulWidget {
  final DownloadTaskInfo config;
  final double threshold;

  const _WaitProgressDialog({required this.config, required this.threshold});

  @override
  State<_WaitProgressDialog> createState() => _WaitProgressDialogState();
}

class _WaitProgressDialogState extends State<_WaitProgressDialog> {
  Timer? _timer;
  double _progress = 0;
  bool _startupReady = false;

  @override
  void initState() {
    super.initState();
    unawaited(_updateProgress());
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_updateProgress()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _updateProgress() async {
    final double progress = DownloadManager().getProgress(widget.config.hash);
    DownloadManager().prioritizePlaybackRange(
      widget.config.hash,
      widget.config.targetPath,
      0,
      MagnetActionHelper._startupProbeBytes,
    );
    final bool startupReady = await DownloadManager().isRangeReadable(
      widget.config.hash,
      widget.config.targetPath,
      bytes: MagnetActionHelper._startupProbeBytes,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _progress = progress;
      _startupReady = startupReady;
    });

    if (startupReady || progress >= 1.0) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double percent = (_progress * 100).clamp(0, 100).toDouble();

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('正在缓冲播放数据'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _startupReady
                  ? '目标视频起播片段已就绪，正在打开播放器。'
                  : '已缓存 ${percent.toStringAsFixed(1)}%，正在优先下载目标视频的起播片段。',
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: (_progress / widget.threshold).clamp(0, 1).toDouble(),
            ),
            const SizedBox(height: 12),
            const Text(
              '保留少量起播缓冲可降低未写入片段导致的花屏、噪点和卡顿。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('转入后台下载'),
          ),
        ],
      ),
    );
  }
}

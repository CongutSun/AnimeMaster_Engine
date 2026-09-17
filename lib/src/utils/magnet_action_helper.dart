import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../coordinator/torrent_media_resolver.dart';
import '../managers/download_manager.dart';
import '../models/download_task_info.dart';
import '../models/playable_media.dart';
import '../screens/video_player_page.dart';
import 'torrent_stream_server.dart';

class MagnetActionHelper {
  static const double _playbackBufferThreshold = 0.03;
  static const int _startupProbeBytes = 512 * 1024;

  static Future<String?> process(
    BuildContext context,
    String rawSource, {
    required bool autoPlay,
    String preferredTitle = '',
    String subjectTitle = '',
    String episodeLabel = '',
    int bangumiSubjectId = 0,
    int bangumiEpisodeId = 0,
    String fallbackSource = '',
    VoidCallback? onTaskAdded,
  }) async {
    bool loadingDialogOpen = false;
    final cancelToken = CancelToken();
    final stage = ValueNotifier<String>('正在获取资源文件信息…');
    DialogRoute<void>? loadingRoute;
    final navigator = Navigator.of(context, rootNavigator: true);

    loadingRoute = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) cancelToken.cancel('用户取消');
        },
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
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
                const SizedBox(height: 20),
                ValueListenableBuilder<String>(
                  valueListenable: stage,
                  builder: (context, message, _) => Text(
                    message,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => cancelToken.cancel('用户取消'),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    unawaited(navigator.push(loadingRoute));
    loadingDialogOpen = true;

    void closeLoadingDialog() {
      if (!loadingDialogOpen || !context.mounted) {
        return;
      }

      if (loadingRoute?.isActive == true) navigator.removeRoute(loadingRoute!);
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
        fallbackSource: fallbackSource,
        cancelToken: cancelToken,
        onStage: (message) => stage.value = message,
      );

      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      closeLoadingDialog();
      if (!context.mounted) return null;
      var taskInfo = preparedTask.taskInfo;
      if (preparedTask.mediaItems.length > 1) {
        final selected = await showDialog<int>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(autoPlay ? '选择播放文件' : '确认合集下载'),
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('此资源包含多个文件，将下载整个资源包。请选择播放文件；如只想下载一集，请取消并选择单集资源。'),
              ),
              for (int i = 0; i < preparedTask.mediaItems.length; i++)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, i),
                  child: Text(preparedTask.mediaItems[i].fileName),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
            ],
          ),
        );
        if (selected == null || !context.mounted) return null;
        final item = preparedTask.mediaItems[selected];
        taskInfo = taskInfo.copyWith(
          targetPath: item.filePath,
          targetSize: item.fileSize,
          episodeLabel: item.episodeLabel,
          bangumiEpisodeId: selected == preparedTask.initialIndex
              ? taskInfo.bangumiEpisodeId
              : 0,
        );
      }

      await DownloadManager().addTask(
        taskInfo,
        preparedTask.torrentBytes,
        streamOptimized: autoPlay,
      );
      onTaskAdded?.call();

      closeLoadingDialog();
      if (!context.mounted) {
        return null;
      }

      if (autoPlay) {
        await _openPreparedPlayback(context, taskInfo);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('任务已加入下载中心。'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      closeLoadingDialog();
      if (cancelToken.isCancelled) return null;
      final message = _friendlyErrorText(error);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
        );
      }
      return message;
    } finally {
      closeLoadingDialog();
      // Route removal disposes the listener before releasing the notifier.
      await Future<void>.delayed(Duration.zero);
      stage.dispose();
    }
    return null;
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
            const LinearProgressIndicator(),
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

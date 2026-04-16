import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../coordinator/torrent_media_resolver.dart';
import '../managers/download_manager.dart';
import '../models/download_task_info.dart';
import '../models/playable_media.dart';
import '../screens/video_player_page.dart';

class MagnetActionHelper {
  static Future<void> process(
    BuildContext context,
    String rawSource, {
    required bool autoPlay,
    String preferredTitle = '',
    String subjectTitle = '',
    String episodeLabel = '',
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
      );

      await DownloadManager().addTask(
        preparedTask.taskInfo,
        preparedTask.torrentBytes,
      );

      closeLoadingDialog();
      if (!context.mounted) {
        return;
      }

      if (autoPlay) {
        await _showWaitAndPlayDialog(context, preparedTask.taskInfo);
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

  static Future<void> _showWaitAndPlayDialog(
    BuildContext context,
    DownloadTaskInfo config,
  ) async {
    final bool shouldPlay =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) =>
              _WaitProgressDialog(config: config),
        ) ??
        false;

    if (!shouldPlay || !context.mounted) {
      return;
    }

    final File localFile = File(config.targetPath);
    final PlayableMedia media = await localFile.exists()
        ? PlayableMedia(
            title: config.displayTitle,
            url: config.targetPath,
            isLocal: true,
            localFilePath: config.targetPath,
            subjectTitle: config.subjectTitle,
            episodeLabel: config.episodeLabel,
          )
        : PlayableMedia(
            title: config.displayTitle,
            url: config.url,
            localFilePath: config.targetPath,
            subjectTitle: config.subjectTitle,
            episodeLabel: config.episodeLabel,
          );

    if (!context.mounted) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (BuildContext context) => VideoPlayerPage(media: media),
      ),
    );
  }
}

class _WaitProgressDialog extends StatefulWidget {
  final DownloadTaskInfo config;

  const _WaitProgressDialog({required this.config});

  @override
  State<_WaitProgressDialog> createState() => _WaitProgressDialogState();
}

class _WaitProgressDialogState extends State<_WaitProgressDialog> {
  late final Timer _timer;
  double _progress = 0.0;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (_isFinished) {
        return;
      }

      final double progress = DownloadManager().getProgress(widget.config.hash);
      if (mounted) {
        setState(() {
          _progress = progress;
        });
      }

      if (progress >= 0.03 || progress == 1.0) {
        _isFinished = true;
        _timer.cancel();
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '正在缓冲数据',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            '将等待下载达到 3% 后自动播放，保证边下边播更稳定。',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 24),
          LinearProgressIndicator(
            value: _progress,
            backgroundColor: Colors.grey.withValues(alpha: 0.2),
            color: Colors.blueAccent,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Text(
            '${(_progress * 100).toStringAsFixed(1)}%',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            _timer.cancel();
            Navigator.of(context).pop(false);
          },
          child: const Text('转入后台下载', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }
}

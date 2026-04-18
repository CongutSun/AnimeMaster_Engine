import 'dart:io';

import 'package:flutter/material.dart';

import '../managers/download_manager.dart';
import '../models/download_task_info.dart';
import '../models/playable_media.dart';
import '../utils/magnet_action_helper.dart';
import 'video_player_page.dart';

class DownloadCenterPage extends StatelessWidget {
  const DownloadCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DownloadManager(),
      builder: (BuildContext context, Widget? child) {
        final DownloadManager manager = DownloadManager();
        final List<DownloadTaskInfo> tasks = manager.allTasks.reversed.toList();

        return Scaffold(
          appBar: AppBar(title: const Text('缓存中心')),
          body: tasks.isEmpty
              ? const Center(
                  child: Text(
                    '当前没有下载任务。',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: tasks.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final DownloadTaskInfo config = tasks[index];
                    final double progress = manager.getProgress(config.hash);
                    final double speed = manager.getSpeed(config.hash);
                    final bool isPaused = manager.isPaused(config.hash);
                    final bool isCompleted = progress >= 1.0;

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.download_for_offline_rounded,
                                    color: Colors.blueAccent,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        config.displayTitle,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          height: 1.35,
                                        ),
                                      ),
                                      if (config
                                          .displaySubtitle
                                          .isNotEmpty) ...<Widget>[
                                        const SizedBox(height: 6),
                                        Text(
                                          config.displaySubtitle,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      Text(
                                        '任务哈希：${config.hash}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            LinearProgressIndicator(
                              value: isCompleted ? 1.0 : progress,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(4),
                              color: isCompleted
                                  ? Colors.green
                                  : (isPaused
                                        ? Colors.grey
                                        : Colors.blueAccent),
                              backgroundColor: Colors.grey.withValues(
                                alpha: 0.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _buildStatusText(
                                progress: progress,
                                isPaused: isPaused,
                                isCompleted: isCompleted,
                                speed: speed,
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: isCompleted
                                    ? Colors.green
                                    : (isPaused
                                          ? Colors.grey
                                          : Colors.blueAccent),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: <Widget>[
                                IconButton(
                                  tooltip: '播放',
                                  icon: const Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: Colors.green,
                                  ),
                                  onPressed: () => _playVideo(context, config),
                                ),
                                if (!isCompleted)
                                  IconButton(
                                    tooltip: isPaused ? '继续' : '暂停',
                                    icon: Icon(
                                      isPaused
                                          ? Icons.play_arrow_rounded
                                          : Icons.pause_rounded,
                                    ),
                                    onPressed: () =>
                                        manager.toggleTask(config.hash),
                                  ),
                                IconButton(
                                  tooltip: '删除',
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () => _confirmDelete(
                                    context,
                                    manager,
                                    config.hash,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showAddMagnetDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('添加任务'),
          ),
        );
      },
    );
  }

  String _buildStatusText({
    required double progress,
    required bool isPaused,
    required bool isCompleted,
    required double speed,
  }) {
    if (isCompleted) {
      return '已完成';
    }
    if (isPaused) {
      return '已暂停  ·  ${(progress * 100).toStringAsFixed(1)}%';
    }
    return '${(progress * 100).toStringAsFixed(1)}%  ·  ${_formatSpeed(speed)}';
  }

  String _formatSpeed(double speedInKb) {
    if (speedInKb >= 1024) {
      return '${(speedInKb / 1024).toStringAsFixed(2)} MB/s';
    }
    return '${speedInKb.toStringAsFixed(1)} KB/s';
  }

  void _showAddMagnetDialog(BuildContext context) {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController sourceController = TextEditingController();

    void submit(BuildContext dialogContext, bool autoPlay) {
      final String rawSource = sourceController.text.trim();
      final String preferredTitle = titleController.text.trim();
      Navigator.pop(dialogContext);
      if (rawSource.isNotEmpty) {
        MagnetActionHelper.process(
          context,
          rawSource,
          autoPlay: autoPlay,
          preferredTitle: preferredTitle,
        );
      }
    }

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final MediaQueryData media = MediaQuery.of(dialogContext);
        final double maxHeight =
            (media.size.height -
                    media.viewInsets.bottom -
                    media.padding.top -
                    media.padding.bottom -
                    48)
                .clamp(280.0, 560.0);

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '手动添加任务',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          TextField(
                            controller: titleController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: '显示标题（可选）',
                              hintText: '例如：葬送的芙莉莲 第12话',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: sourceController,
                            minLines: 3,
                            maxLines: 5,
                            textInputAction: TextInputAction.newline,
                            decoration: const InputDecoration(
                              labelText: '资源链接',
                              hintText: '支持 magnet、40 位 Hash 或 .torrent 直链',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SafeArea(
                    top: false,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => submit(dialogContext, false),
                            child: const Text('仅添加'),
                          ),
                          FilledButton(
                            onPressed: () => submit(dialogContext, true),
                            child: const Text('添加并播放'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      titleController.dispose();
      sourceController.dispose();
    });
  }

  void _playVideo(BuildContext context, DownloadTaskInfo config) {
    final File localFile = File(config.targetPath);
    final PlayableMedia media = localFile.existsSync()
        ? PlayableMedia(
            title: config.displayTitle,
            url: config.targetPath,
            isLocal: true,
            localFilePath: config.targetPath,
            subjectTitle: config.subjectTitle,
            episodeLabel: config.episodeLabel,
            bangumiSubjectId: config.bangumiSubjectId,
            bangumiEpisodeId: config.bangumiEpisodeId,
          )
        : PlayableMedia(
            title: config.displayTitle,
            url: config.url,
            localFilePath: config.targetPath,
            subjectTitle: config.subjectTitle,
            episodeLabel: config.episodeLabel,
            bangumiSubjectId: config.bangumiSubjectId,
            bangumiEpisodeId: config.bangumiEpisodeId,
          );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (BuildContext context) => VideoPlayerPage(media: media),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    DownloadManager manager,
    String hash,
  ) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除任务'),
        content: const Text('删除后会一并移除已下载文件，确认继续吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              manager.deleteTask(hash);
              Navigator.pop(dialogContext);
            },
            child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

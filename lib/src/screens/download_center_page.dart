import 'dart:io';

import 'package:flutter/material.dart';

import '../api/bangumi_api.dart';
import '../core/service_locator.dart';
import '../managers/download_manager.dart';
import '../models/download_task_info.dart';
import '../models/playable_media.dart';
import '../utils/magnet_action_helper.dart';
import '../utils/task_title_parser.dart';
import '../utils/torrent_stream_server.dart';
import 'video_player_page.dart';

class DownloadCenterPage extends StatelessWidget {
  const DownloadCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final DownloadManager manager = ServiceLocator.downloadManager;
    return ListenableBuilder(
      listenable: manager,
      builder: (BuildContext context, Widget? child) {
        final List<DownloadTaskInfo> tasks = manager.allTasks.reversed.toList();
        final ColorScheme colors = Theme.of(context).colorScheme;

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
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 112),
                  itemCount: tasks.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final DownloadTaskInfo config = tasks[index];
                    final double progress = manager.getProgress(config.hash);
                    final double speed = manager.getSpeed(config.hash);
                    final double uploadSpeed = manager.getUploadSpeed(
                      config.hash,
                    );
                    final bool isPaused = manager.isPaused(config.hash);
                    final bool isQueued = manager.isQueued(config.hash);
                    final bool isCompleted = progress >= 1.0;
                    final bool isSeeding = manager.isSeeding(config.hash);
                    final Color statusColor = isSeeding
                        ? colors.tertiary
                        : (isCompleted
                              ? colors.primary
                              : (isPaused || isQueued
                                    ? colors.onSurfaceVariant
                                    : colors.primary));

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
                                    color: colors.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    Icons.download_for_offline_rounded,
                                    color: colors.primary,
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
                                      if (config.displaySubtitle.isNotEmpty ||
                                          config.bangumiSubjectId >
                                              0) ...<Widget>[
                                        const SizedBox(height: 6),
                                        FutureBuilder<DownloadTaskInfo>(
                                          future: _enrichTaskEpisodeLabel(
                                            config,
                                          ),
                                          builder:
                                              (
                                                BuildContext context,
                                                AsyncSnapshot<DownloadTaskInfo>
                                                snapshot,
                                              ) {
                                                if (snapshot.hasError) {
                                                  return Text(
                                                    config.episodeLabel.isNotEmpty
                                                        ? config.episodeLabel
                                                        : config.title,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: colors.onSurfaceVariant,
                                                    ),
                                                  );
                                                }
                                                final DownloadTaskInfo task =
                                                    snapshot.data ?? config;
                                                return Text(
                                                  task
                                                          .displaySubtitle
                                                          .isNotEmpty
                                                      ? task.displaySubtitle
                                                      : '正在匹配剧集信息...',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        colors.onSurfaceVariant,
                                                  ),
                                                );
                                              },
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      Text(
                                        '任务哈希：${config.hash}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colors.onSurfaceVariant,
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
                              color: statusColor,
                              backgroundColor: colors.surfaceContainerHighest
                                  .withValues(
                                    alpha:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? 0.72
                                        : 0.9,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                _buildStatusText(
                                  progress: progress,
                                  isPaused: isPaused,
                                  isQueued: isQueued,
                                  isCompleted: isCompleted,
                                  isSeeding: isSeeding,
                                  speed: speed,
                                  uploadSpeed: uploadSpeed,
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: statusColor,
                                  fontWeight: FontWeight.w700,
                                ),
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
                                IconButton(
                                  tooltip: isPaused || isQueued
                                      ? (isCompleted ? '开始做种' : '继续')
                                      : (isCompleted ? '暂停做种' : '暂停'),
                                  icon: Icon(
                                    isPaused || isQueued
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
    required bool isQueued,
    required bool isCompleted,
    required bool isSeeding,
    required double speed,
    required double uploadSpeed,
  }) {
    if (isSeeding) {
      return '做种中  ·  上传 ${_formatSpeed(uploadSpeed)}';
    }
    if (isQueued) {
      return isCompleted
          ? '做种排队中'
          : '排队中  ·  ${(progress * 100).toStringAsFixed(1)}%';
    }
    if (isCompleted) {
      return isPaused ? '已完成  ·  做种已暂停' : '已完成';
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

  Future<DownloadTaskInfo> _enrichTaskEpisodeLabel(
    DownloadTaskInfo config,
  ) async {
    if (config.bangumiSubjectId <= 0 ||
        config.episodeLabel.contains('·') ||
        config.episodeLabel.contains('集 ·')) {
      return config;
    }

    final List<Map<String, dynamic>> episodes =
        await BangumiApi.getSubjectEpisodes(config.bangumiSubjectId);
    if (episodes.isEmpty) {
      return config;
    }

    Map<String, dynamic>? match;
    if (config.bangumiEpisodeId > 0) {
      match = episodes.firstWhere(
        (Map<String, dynamic> episode) =>
            int.tryParse(episode['id']?.toString() ?? '') ==
            config.bangumiEpisodeId,
        orElse: () => <String, dynamic>{},
      );
      if (match.isEmpty) {
        match = null;
      }
    }

    final int? episodeNumber = TaskTitleParser.extractEpisodeNumber(
      '${config.episodeLabel} ${config.title}',
    );
    if (match == null && episodeNumber != null) {
      match = episodes.firstWhere(
        (Map<String, dynamic> episode) =>
            _numberValue(episode['ep']) == episodeNumber ||
            _numberValue(episode['sort']) == episodeNumber,
        orElse: () => <String, dynamic>{},
      );
      if (match.isEmpty) {
        match = null;
      }
    }

    if (match == null) {
      return config;
    }

    final int number =
        _numberValue(match['ep']) ?? _numberValue(match['sort']) ?? 0;
    final String episodeTitle =
        (match['name_cn']?.toString().trim().isNotEmpty == true
                ? match['name_cn']
                : match['name'])
            ?.toString()
            .trim() ??
        '';
    final String episodeLabel = TaskTitleParser.buildEpisodeDisplayLabel(
      episodeNumber: number,
      episodeTitle: episodeTitle,
    );
    if (episodeLabel.isEmpty) {
      return config;
    }

    return config.copyWith(
      episodeLabel: episodeLabel,
      bangumiEpisodeId: int.tryParse(match['id']?.toString() ?? ''),
    );
  }

  int? _numberValue(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '');
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
            (media.size.height - media.padding.top - media.padding.bottom - 48)
                .clamp(320.0, 560.0);

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
                            scrollPadding: const EdgeInsets.only(bottom: 96),
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

  Future<void> _playVideo(BuildContext context, DownloadTaskInfo config) async {
    final DownloadTaskInfo playConfig = await _enrichTaskEpisodeLabel(config);
    await DownloadManager().prepareForPlayback(playConfig.hash);
    final File localFile = File(playConfig.targetPath);
    final bool canUseLocalFile =
        playConfig.isCompleted && localFile.existsSync();
    TorrentStreamServer? streamServer;
    final PlayableMedia media;
    if (canUseLocalFile) {
      media = PlayableMedia(
        title: playConfig.displayTitle,
        url: playConfig.targetPath,
        isLocal: true,
        localFilePath: playConfig.targetPath,
        subjectTitle: playConfig.subjectTitle,
        episodeLabel: playConfig.episodeLabel,
        bangumiSubjectId: playConfig.bangumiSubjectId,
        bangumiEpisodeId: playConfig.bangumiEpisodeId,
      );
    } else if (playConfig.targetSize > 0) {
      DownloadManager().prioritizePlaybackRange(
        playConfig.hash,
        playConfig.targetPath,
        0,
        512 * 1024,
      );
      streamServer = TorrentStreamServer(
        videoFilePath: playConfig.targetPath,
        videoSize: playConfig.targetSize,
        infoHash: playConfig.hash,
      );
      final String streamUrl = await streamServer.start();
      media = PlayableMedia(
        title: playConfig.displayTitle,
        url: streamUrl,
        localFilePath: playConfig.targetPath,
        subjectTitle: playConfig.subjectTitle,
        episodeLabel: playConfig.episodeLabel,
        bangumiSubjectId: playConfig.bangumiSubjectId,
        bangumiEpisodeId: playConfig.bangumiEpisodeId,
      );
    } else {
      media = PlayableMedia(
        title: playConfig.displayTitle,
        url: playConfig.url,
        localFilePath: playConfig.targetPath,
        subjectTitle: playConfig.subjectTitle,
        episodeLabel: playConfig.episodeLabel,
        bangumiSubjectId: playConfig.bangumiSubjectId,
        bangumiEpisodeId: playConfig.bangumiEpisodeId,
      );
    }

    if (!context.mounted) {
      streamServer?.stop();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (BuildContext context) =>
            VideoPlayerPage(media: media, streamServer: streamServer),
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

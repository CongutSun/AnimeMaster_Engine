import '../widgets/app_feedback.dart';
import 'magnet_config_page.dart';
import 'dart:io';
import '../theme/app_theme.dart';

import 'package:flutter/material.dart';

import '../api/bangumi_api.dart';
import '../core/service_locator.dart';
import '../managers/download_manager.dart';
import '../models/download_task_info.dart';
import '../utils/cached_media_playback.dart';
import '../services/background_download_service.dart';
import '../utils/magnet_action_helper.dart';
import '../utils/task_title_parser.dart';
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

        final active = tasks.where((t) => !t.isCompleted);
        final complete = tasks.where((t) => t.isCompleted);
        final rows = <Object>[
          if (active.isNotEmpty) '下载任务',
          ...active,
          if (complete.isNotEmpty) '可离线观看',
          ...complete,
        ];

        return Scaffold(
          appBar: AppBar(
            title: const Text('下载中心'),
            actions: <Widget>[
              PopupMenuButton<bool>(
                tooltip: '做种设置',
                icon: const Icon(Icons.upload_outlined),
                onSelected: (enabled) async {
                  try {
                    await manager.setSeedingEnabled(enabled);
                  } catch (_) {
                    if (context.mounted) {
                      AppFeedback.show(
                        context,
                        const SnackBar(content: Text('做种设置未能应用，请重试。')),
                      );
                    }
                  }
                },
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    value: true,
                    checked: manager.seedingEnabled,
                    child: const Text('空闲时做种'),
                  ),
                  CheckedPopupMenuItem(
                    value: false,
                    checked: !manager.seedingEnabled,
                    child: const Text('完成后停止做种'),
                  ),
                ],
              ),
              if (Platform.isAndroid)
                IconButton(
                  tooltip: '后台下载设置',
                  icon: const Icon(Icons.battery_saver_outlined),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (BuildContext dialogContext) => AlertDialog(
                      title: const Text('后台下载'),
                      content: const Text(
                        '下载时请允许通知，并在系统应用设置中允许后台运行或选择“不限制”电池用量。系统强行停止应用后，需要重新打开才能继续。',
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('关闭'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            BackgroundDownloadService.openSettings();
                          },
                          child: const Text('打开系统设置'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          body: tasks.isEmpty
              ? const Center(
                  child: Text(
                    '当前没有下载任务。',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    if (row is String) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
                        child: Text(
                          row,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      );
                    }
                    return _taskCard(context, manager, row as DownloadTaskInfo);
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

  Widget _taskCard(
    BuildContext context,
    DownloadManager manager,
    DownloadTaskInfo task,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hash = task.hash;
    final complete = task.isCompleted;
    final paused = manager.isPaused(hash);
    final queued = manager.isQueued(hash);
    final progress = manager.getProgress(hash);
    final seeding = manager.isSeeding(hash);
    final seedingOff = complete && !manager.seedingEnabled;
    final status = task.isBilibili
        ? manager.bilibiliStatus(task)
        : _buildStatusText(
            progress: progress,
            isPaused: paused,
            isQueued: queued,
            isCompleted: complete,
            isSeeding: seeding,
            seedingOff: seedingOff,
            speed: manager.getSpeed(hash),
            uploadSpeed: manager.getUploadSpeed(hash),
          );
    final statusColor = complete
        ? AppTheme.success(context)
        : paused || queued
        ? colors.onSurfaceVariant
        : colors.primary;
    final resume = paused || (!complete && queued);
    return Card(
      key: ValueKey(hash),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.displayTitle, style: theme.textTheme.titleMedium),
            if (task.displaySubtitle.isNotEmpty)
              Text(
                task.displaySubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 8),
            if (!complete) ...[
              LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
              const SizedBox(height: 8),
            ],
            Text(
              status,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: statusColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (!complete && !task.isBilibili && !paused && !queued)
              Text(
                manager.getConnectedPeers(hash) == 0
                    ? '正在寻找可用连接…'
                    : '已连接 ${manager.getConnectedPeers(hash)} 个节点',
                style: theme.textTheme.bodyMedium,
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!task.isBilibili || complete)
                  IconButton(
                    tooltip: '播放',
                    icon: const Icon(Icons.play_circle_fill_rounded),
                    onPressed: () => _playVideo(context, task),
                  ),
                if (!complete)
                  IconButton(
                    tooltip: resume ? (task.isBilibili ? '重新缓存' : '继续') : '暂停',
                    icon: Icon(
                      resume ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    ),
                    onPressed: () => manager.toggleTask(hash),
                  ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: '更多',
                  onSelected: (action) {
                    if (action == 'alternate') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MagnetConfigPage(
                            animeName: task.subjectTitle.isEmpty
                                ? task.title
                                : task.subjectTitle,
                            aliases: const [],
                            bangumiSubjectId: task.bangumiSubjectId,
                            initialEpisodeNumber:
                                task.files
                                    .where((f) => f.path == task.targetPath)
                                    .firstOrNull
                                    ?.number ??
                                0,
                            excludeHash: task.hash,
                          ),
                        ),
                      );
                    }
                    if (action == 'assign') _assign(context, manager, task);
                    if (action == 'seed') manager.toggleTask(hash);
                    if (action == 'delete') {
                      _confirmDelete(context, manager, hash);
                    }
                    if (action == 'details') {
                      showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          scrollable: true,
                          title: const Text('任务详情'),
                          content: FutureBuilder<DownloadTaskInfo>(
                            future: _enrichTaskEpisodeLabel(task),
                            builder: (context, snapshot) => SelectableText(
                              [
                                task.displayTitle,
                                (snapshot.data ?? task).displaySubtitle,
                                status,
                                if (!task.isBilibili) '任务哈希：$hash',
                              ].where((line) => line.isNotEmpty).join('\n'),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    if (complete && !task.isBilibili)
                      PopupMenuItem(
                        value: 'seed',
                        enabled: !seedingOff,
                        child: Text(
                          seedingOff
                              ? '做种已关闭'
                              : paused
                              ? '开始做种'
                              : '暂停做种',
                        ),
                      ),
                    if (!complete && !task.isBilibili)
                      const PopupMenuItem(
                        value: 'alternate',
                        child: Text('搜索其他版本'),
                      ),
                    if (task.files.isNotEmpty)
                      const PopupMenuItem(value: 'assign', child: Text('校正集数')),
                    const PopupMenuItem(value: 'details', child: Text('任务详情')),
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _buildStatusText({
    required double progress,
    required bool isPaused,
    required bool isQueued,
    required bool isCompleted,
    required bool isSeeding,
    required bool seedingOff,
    required double speed,
    required double uploadSpeed,
  }) {
    if (isSeeding) {
      return '做种中  ·  上传 ${_formatSpeed(uploadSpeed)}';
    }
    if (seedingOff) return '已完成  ·  做种已关闭';
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
    if (config.files.isNotEmpty ||
        config.isBilibili ||
        config.bangumiSubjectId <= 0 ||
        config.episodeLabel.contains('·') ||
        config.episodeLabel.contains('集 ·')) {
      return config;
    }

    final List<Map<String, dynamic>> episodes = await BangumiApi.instance
        .getSubjectEpisodes(config.bangumiSubjectId);
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

  Future<DownloadTaskInfo?> _chooseFile(
    BuildContext context,
    DownloadTaskInfo task,
  ) async {
    if (task.files.length <= 1) return task;
    return showDialog<DownloadTaskInfo>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择剧集文件'),
        children: [
          for (final f in task.files)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, task.forFile(f)),
              child: Text(
                '${f.label}\n${f.path.split(RegExp(r"[/\\\\]")).last}',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _assign(
    BuildContext context,
    DownloadManager manager,
    DownloadTaskInfo task,
  ) async {
    final selection = await _chooseFile(context, task);
    if (selection == null || !context.mounted) return;
    int? number;
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('校正集数'),
        content: TextField(
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '正片集数'),
          onChanged: (s) => number = int.tryParse(s.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if ((number ?? 0) > 0) Navigator.pop(ctx, number);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (selected != null) {
      await manager.assignEpisode(task.hash, selection.targetPath, selected);
    }
  }

  Future<void> _playVideo(BuildContext context, DownloadTaskInfo config) async {
    final chosen = await _chooseFile(context, config);
    if (chosen == null) return;
    config = chosen;
    final DownloadTaskInfo playConfig = config.bangumiEpisodeId > 0
        ? config
        : await _enrichTaskEpisodeLabel(config);
    final CachedPlaybackSession session;
    try {
      session = await CachedMediaPlayback.prepare(playConfig);
    } catch (error) {
      if (context.mounted) {
        AppFeedback.show(context, SnackBar(content: Text('无法播放：$error')));
      }
      return;
    }

    if (!context.mounted) {
      session.streamServer?.stop();
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (BuildContext context) => VideoPlayerPage(
          media: session.media,
          streamServer: session.streamServer,
        ),
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
            onPressed: () async {
              final bool deleted = await manager.deleteTask(hash);
              if (!dialogContext.mounted) {
                return;
              }
              Navigator.pop(dialogContext);
              if (!deleted && context.mounted) {
                AppFeedback.show(
                  context,
                  const SnackBar(content: Text('删除失败，任务文件未被移除。')),
                );
              }
            },
            child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

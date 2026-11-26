import 'package:flutter/material.dart';

import '../storage/app_database.dart';
import '../utils/episode_helpers.dart';
import '../utils/format_helpers.dart';
import '../utils/playback_progress_store.dart';
import '../utils/task_title_parser.dart';

class SubjectPlaybackActions extends StatefulWidget {
  const SubjectPlaybackActions({
    super.key,
    required this.history,
    required this.episodes,
    required this.watchOffline,
    required this.onResume,
    required this.onSearch,
  });

  final Stream<PlaybackProgressRecord?>? history;
  final List<Map<String, dynamic>> episodes;
  final Stream<bool> Function(int episodeId, String previousPath) watchOffline;
  final void Function(
    Map<String, dynamic> episode,
    PlaybackProgressRecord record,
  )
  onResume;
  final VoidCallback onSearch;

  @override
  State<SubjectPlaybackActions> createState() => _SubjectPlaybackActionsState();
}

class _SubjectPlaybackActionsState extends State<SubjectPlaybackActions> {
  (int, String)? _cacheKey;
  Stream<bool>? _offline;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackProgressRecord?>(
      stream: widget.history,
      builder: (context, snapshot) {
        final record = snapshot.data;
        final progress = record == null
            ? null
            : PlaybackProgressStore.snapshotFromRecord(record);
        if (record == null || progress == null) {
          _cacheKey = null;
          _offline = null;
          return FilledButton.icon(
            onPressed: widget.onSearch,
            icon: const Icon(Icons.travel_explore),
            label: const Text('搜索资源'),
          );
        }
        final cacheKey = (record.bangumiEpisodeId, record.localFilePath);
        if (_cacheKey != cacheKey) {
          _cacheKey = cacheKey;
          _offline = widget.watchOffline(
            record.bangumiEpisodeId,
            record.localFilePath,
          );
        }
        final episode =
            widget.episodes
                .where((ep) => episodeId(ep) == record.bangumiEpisodeId)
                .firstOrNull ??
            <String, dynamic>{
              'id': record.bangumiEpisodeId,
              'ep': TaskTitleParser.extractEpisodeNumber(
                TaskTitleParser.extractEpisodeLabel(record.episodeLabel),
              ),
              'name': record.episodeLabel,
            };
        final number = episodeNumber(episode);
        final label = number > 0 ? '继续看第 $number 集' : '继续观看';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StreamBuilder<bool>(
              key: ValueKey(cacheKey),
              stream: _offline,
              builder: (context, cached) => Text(
                '上次看到 ${formatDuration(progress.position)}${cached.data == true ? ' · 已缓存' : ''}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => widget.onResume(episode, record),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(label),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '搜索资源',
                  onPressed: widget.onSearch,
                  icon: const Icon(Icons.travel_explore),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

import 'dart:convert';
import '../models/cache_episode_file.dart';
import '../models/playable_media.dart';
import '../utils/playback_progress_store.dart';
import 'package:drift/drift.dart';

import '../models/download_task_info.dart';
import '../storage/app_database.dart';

class DownloadTaskRepository {
  DownloadTaskRepository(this._database);

  static final DownloadTaskRepository instance = DownloadTaskRepository(
    AppDatabase.instance,
  );

  final AppDatabase _database;

  Stream<bool> watchOfflineEpisode(
    int subjectId,
    int episodeId,
    String previousPath,
  ) {
    final query = _database.select(_database.downloadTaskRecords)
      ..where(
        (t) =>
            t.isCompleted.equals(true) &
            (t.bangumiSubjectId.equals(subjectId) |
                t.bangumiSubjectId.equals(0)),
      );
    return query.watch().asyncMap((rows) async {
      final episode =
          await (_database.select(_database.animeEpisodes)..where(
                (t) => t.id.equals(episodeId) & t.subjectId.equals(subjectId),
              ))
              .getSingleOrNull();
      for (final row in rows) {
        final task = _fromRecord(row);
        for (final item in task.playableFiles) {
          final index = item.files.firstOrNull;
          final matches = item.bangumiEpisodeId > 0
              ? item.bangumiEpisodeId == episodeId
              : index != null
              ? task.bangumiSubjectId == subjectId &&
                    index.number > 0 &&
                    index.number == episode?.episodeNumber
              : previousPath.isNotEmpty && previousPath == item.targetPath;
          if (matches && await item.hasCompleteFile()) return true;
        }
      }
      return false;
    }).distinct();
  }

  Future<List<DownloadTaskInfo>> loadAll() async {
    final List<DownloadTaskRecord> rows = await _database
        .select(_database.downloadTaskRecords)
        .get();
    return rows.map(_fromRecord).toList(growable: false);
  }

  Future<void> upsert(DownloadTaskInfo task) async {
    await _database
        .into(_database.downloadTaskRecords)
        .insertOnConflictUpdate(_toCompanion(task));
  }

  Future<void> upsertAll(Iterable<DownloadTaskInfo> tasks) async {
    await _database.batch((Batch batch) {
      batch.insertAllOnConflictUpdate(
        _database.downloadTaskRecords,
        tasks.map(_toCompanion).toList(growable: false),
      );
    });
  }

  Future<List<Map<String, dynamic>>> catalog(int subjectId) async {
    if (subjectId <= 0) return [];
    final rows = await (_database.select(
      _database.animeEpisodes,
    )..where((t) => t.subjectId.equals(subjectId))).get();
    return [
      for (final r in rows)
        {
          'id': r.id,
          'ep': r.episodeNumber,
          'name': r.title,
          'name_cn': r.titleCn,
        },
    ];
  }

  Future<CacheEpisodeFile> legacyPartBinding(
    DownloadTaskInfo task,
    CacheEpisodeFile file,
    List<Map<String, dynamic>> episodes,
  ) async {
    if (file.episodeId > 0) return file;
    final match = DownloadTaskInfo.bilibiliKey.firstMatch(task.hash);
    if (match == null) return file;
    final records =
        await (_database.select(_database.bilibiliEpisodeMappings)..where(
              (t) =>
                  t.bvid.equals(match[1]!) & t.cid.equals(int.parse(match[2]!)),
            ))
            .get();
    if (records.length != 1 || !file.label.startsWith('待确认 · ')) return file;
    final key = records.single.mappingKey;
    final found = episodes
        .where(
          (e) =>
              key == 'episode:${e['id']}' ||
              key == 'subject:${task.bangumiSubjectId}:episode:${e['ep']}',
        )
        .toList();
    if (found.length != 1) return file;
    final number = found.single['ep'] as int;
    if (number <= 0) return file;
    final saved = CacheEpisodeFile.identify(
      file.path,
      file.size,
      '第 $number 集',
      subject: task.subjectTitle,
      catalog: found,
    );
    return saved.bind(saved.episodeId, saved.label, number, confirmed: true);
  }

  Future<void> saveIndex(DownloadTaskInfo task) =>
      _database.transaction(() async {
        await upsert(task);
        for (final f in task.files) {
          final media = PlayableMedia(
            title: task.displayTitle,
            url: f.path,
            localFilePath: f.path,
            episodeLabel: f.label,
            subjectTitle: task.subjectTitle,
            bangumiSubjectId: task.bangumiSubjectId,
            bangumiEpisodeId: f.episodeId,
            bilibiliCacheIdentity: task.bilibiliIdentity,
          );
          final key = PlaybackProgressStore.keyFor(media);
          final table = _database.playbackProgressRecords;
          final rows =
              await (_database.select(table)..where(
                    (t) =>
                        t.localFilePath.equals(f.path) |
                        (task.isBilibili
                            ? t.mediaKey.equals(key)
                            : const Constant(false)),
                  ))
                  .get();
          for (final row in rows) {
            if (row.mediaKey != key) {
              final dest = await (_database.select(
                table,
              )..where((t) => t.mediaKey.equals(key))).getSingleOrNull();
              if (dest == null || row.updatedAtMs > dest.updatedAtMs) {
                await _database
                    .into(table)
                    .insertOnConflictUpdate(
                      row.copyWith(
                        mediaKey: key,
                        bangumiSubjectId: task.bangumiSubjectId,
                        bangumiEpisodeId: f.episodeId,
                        episodeLabel: f.label,
                      ),
                    );
              }
              await (_database.delete(
                table,
              )..where((t) => t.mediaKey.equals(row.mediaKey))).go();
            } else {
              await (_database.update(
                table,
              )..where((t) => t.mediaKey.equals(key))).write(
                PlaybackProgressRecordsCompanion(
                  bangumiSubjectId: Value(task.bangumiSubjectId),
                  bangumiEpisodeId: Value(f.episodeId),
                  episodeLabel: Value(f.label),
                ),
              );
            }
          }
        }
      });

  Future<void> deleteByHash(String hash) async {
    await (_database.delete(
      _database.downloadTaskRecords,
    )..where((DownloadTaskRecords table) => table.hash.equals(hash))).go();
  }

  DownloadTaskInfo _fromRecord(DownloadTaskRecord record) {
    return DownloadTaskInfo(
      files: [
        for (final f in jsonDecode(record.episodeFiles) as List)
          CacheEpisodeFile.fromJson(Map<String, dynamic>.from(f)),
      ],
      hash: record.hash,
      title: record.title,
      url: record.url,
      savePath: record.savePath,
      targetPath: record.targetPath,
      targetSize: record.targetSize,
      audioSize: record.audioSize,
      subjectTitle: record.subjectTitle,
      episodeLabel: record.episodeLabel,
      bangumiSubjectId: record.bangumiSubjectId,
      bangumiEpisodeId: record.bangumiEpisodeId,
      isCompleted: record.isCompleted,
      isPaused: record.isPaused,
    );
  }

  DownloadTaskRecordsCompanion _toCompanion(DownloadTaskInfo task) {
    return DownloadTaskRecordsCompanion.insert(
      hash: task.hash,
      episodeFiles: Value(
        jsonEncode(task.files.map((f) => f.toJson()).toList()),
      ),
      title: Value(task.title),
      url: Value(task.url),
      savePath: Value(task.savePath),
      targetPath: Value(task.targetPath),
      targetSize: Value(task.targetSize),
      audioSize: Value(task.audioSize),
      subjectTitle: Value(task.subjectTitle),
      episodeLabel: Value(task.episodeLabel),
      bangumiSubjectId: Value(task.bangumiSubjectId),
      bangumiEpisodeId: Value(task.bangumiEpisodeId),
      isCompleted: Value(task.isCompleted),
      isPaused: Value(task.isPaused),
      updatedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
    );
  }
}

import 'package:drift/drift.dart';

import '../models/download_task_info.dart';
import '../storage/app_database.dart';

class DownloadTaskRepository {
  DownloadTaskRepository._(this._database);

  static final DownloadTaskRepository instance = DownloadTaskRepository._(
    AppDatabase.instance,
  );

  final AppDatabase _database;

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

  Future<void> deleteByHash(String hash) async {
    await (_database.delete(
      _database.downloadTaskRecords,
    )..where((DownloadTaskRecords table) => table.hash.equals(hash))).go();
  }

  DownloadTaskInfo _fromRecord(DownloadTaskRecord record) {
    return DownloadTaskInfo(
      hash: record.hash,
      title: record.title,
      url: record.url,
      savePath: record.savePath,
      targetPath: record.targetPath,
      targetSize: record.targetSize,
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
      title: Value(task.title),
      url: Value(task.url),
      savePath: Value(task.savePath),
      targetPath: Value(task.targetPath),
      targetSize: Value(task.targetSize),
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

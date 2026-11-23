import 'dart:io';

import 'package:animemaster/src/models/download_task_info.dart';
import 'package:animemaster/src/models/online_episode_source.dart';
import 'package:animemaster/src/repositories/download_task_repository.dart';
import 'package:animemaster/src/repositories/playback_progress_repository.dart';
import 'package:animemaster/src/storage/app_database.dart';
import 'package:animemaster/src/utils/cached_media_playback.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const query = OnlineEpisodeQuery(
  bangumiSubjectId: 12,
  bangumiEpisodeId: 140,
  subjectTitle: '测试番',
  aliases: [],
  episodeNumber: 40,
  episodeTitle: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late DownloadTaskInfo task;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('animemaster-episode-cache-');
    final file = await File('${temp.path}/第40集.mp4').writeAsBytes([1, 2, 3]);
    task = DownloadTaskInfo(
      hash: 'one',
      title: '测试番 第40集',
      url: 'magnet:?xt=test',
      savePath: temp.path,
      targetPath: file.path,
      targetSize: 3,
      isCompleted: true,
      bangumiSubjectId: 12,
      bangumiEpisodeId: 140,
    );
  });
  tearDown(() => temp.delete(recursive: true));

  test('同名其他作品和同号其他剧集不串集，有完整文件时优先直读，兼容旧下载', () async {
    final partial = task.copyWith(isCompleted: false);
    final old = task.copyWith(
      hash: 'old',
      bangumiEpisodeId: 0,
      bangumiSubjectId: 0,
      targetSize: 0,
    );
    final candidates = CachedMediaPlayback.episodeTasks([
      partial,
      old,
      task.copyWith(bangumiSubjectId: 13),
      task.copyWith(bangumiEpisodeId: 141),
    ], query);
    expect(candidates, unorderedEquals([partial, old]));
    final best = await CachedMediaPlayback.preferredTask(candidates);
    expect(best, same(old));
    final session = await CachedMediaPlayback.prepare(best!);
    expect(session.media.isLocal, isTrue);
    expect(session.media.url, task.targetPath);
    expect(session.streamServer, isNull);
  });

  test('文件缺失、为空或被截断均不能标作完整，无完整文件时仍可边下边播', () async {
    final partial = task.copyWith(isCompleted: false);
    for (final invalid in [
      task.copyWith(targetPath: '${temp.path}/missing'),
      task.copyWith(targetSize: 6),
    ]) {
      expect(await CachedMediaPlayback.preferredTask([invalid]), isNull);
      expect(
        await CachedMediaPlayback.preferredTask([invalid, partial]),
        same(partial),
      );
      await expectLater(CachedMediaPlayback.prepare(invalid), throwsStateError);
    }
    await File(task.targetPath).writeAsBytes([]);
    expect(await task.copyWith(targetSize: 0).hasCompleteFile(), isFalse);
  });

  test('续播优先上次实际文件，旧文件与新任务的显式分集冲突时以分集为准', () {
    final old = task.copyWith(
      hash: 'old',
      bangumiSubjectId: 0,
      bangumiEpisodeId: 0,
      targetPath: 'unlabelled.mp4',
      title: 'video',
    );
    final wrong = old.copyWith(bangumiEpisodeId: 141);
    expect(
      CachedMediaPlayback.episodeTasks(
        [task, old, wrong],
        query,
        previousPath: old.targetPath,
      ),
      [old, task],
    );
  });

  test('已缓存状态要求下载记录和文件均有效，也识别上次播放过的旧文件', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final downloads = DownloadTaskRepository(db);
    Future<bool> available() =>
        downloads.watchOfflineEpisode(12, 140, task.targetPath).first;
    await downloads.upsert(task.copyWith(isCompleted: false));
    expect(await available(), isFalse);
    await downloads.upsert(task.copyWith(bangumiSubjectId: 13));
    expect(await available(), isFalse);
    await downloads.upsert(task.copyWith(bangumiEpisodeId: 0));
    expect(await available(), isTrue);
    await downloads.upsert(task.copyWith(bangumiEpisodeId: 141));
    expect(await available(), isFalse);
    await downloads.upsert(task);
    expect(await available(), isTrue);
    await File(task.targetPath).delete();
    expect(await available(), isFalse);
  });

  test('最后观看记录按作品和更新时间选取，忽略无分集关联的记录', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    for (final (subject, ep, time) in [
      (12, 140, 3),
      (12, 102, 1),
      (12, 0, 8),
      (23, 141, 9),
    ]) {
      await db
          .into(db.playbackProgressRecords)
          .insert(
            PlaybackProgressRecordsCompanion.insert(
              mediaKey: '$subject-$ep',
              bangumiSubjectId: Value(subject),
              bangumiEpisodeId: Value(ep),
              updatedAtMs: Value(time),
            ),
          );
    }
    expect(
      (await PlaybackProgressRepository(
        db,
      ).watchLatestEpisode(12).first)?.bangumiEpisodeId,
      140,
    );
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:animemaster/src/managers/download_manager.dart';
import 'package:animemaster/src/models/cache_episode_file.dart';
import 'package:animemaster/src/models/download_task_info.dart';
import 'package:animemaster/src/models/online_episode_source.dart';
import 'package:animemaster/src/models/playable_media.dart';
import 'package:animemaster/src/repositories/download_task_repository.dart';
import 'package:animemaster/src/services/cache_episode_index.dart';
import 'package:animemaster/src/storage/app_database.dart';
import 'package:animemaster/src/utils/cached_media_playback.dart';
import 'package:animemaster/src/utils/playback_progress_store.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:dio/dio.dart';
import 'package:animemaster/src/coordinator/torrent_media_resolver.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const catalog = [
  {'ep': 1, 'id': 101, 'name': '风'},
  {'ep': 2, 'id': 102, 'name': '雨'},
];
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('只匹配本季正片，支持剧集标题、数字、中文、字幕组命名和季集标记', () {
    for (final name in [
      'S01E02.mkv',
      '动画 02 [1080p].mkv',
      '动画.Episode.02.mkv',
      '[字幕组] 动画 - 02 [1080p].mp4',
      '第二話',
      '雨',
      '02.mkv',
      '动画 [02v2].mkv',
    ]) {
      final f = CacheEpisodeFile.identify(
        'a',
        3,
        name,
        subject: '动画',
        catalog: catalog,
      );
      expect(f.episodeId, 102, reason: name);
    }
    for (final name in [
      'S02E02.mkv',
      'S01E01-S01E02.mkv',
      '01-12合集.mkv',
      'EP1.5.mkv',
      'NCOP01.mkv',
      '动画 1080p 10bit.mkv',
    ]) {
      expect(
        CacheEpisodeFile.identify(
          'a',
          3,
          name,
          subject: '动画',
          catalog: catalog,
        ).number,
        0,
        reason: name,
      );
    }
  });
  test('合集生成独立索引，跳过字幕并按集数排序', () async {
    final names = ['EP02.mkv', 'EP01.mkv', 'NCOP.mkv', 'EP01.ass'];
    final entries = names
        .map((n) => 'd6:lengthi1e4:pathl${n.length}:${n}ee')
        .join();
    final bytes = Uint8List.fromList(
      ascii.encode(
        'd4:infod5:filesl${entries}e4:name4:Pack12:piece lengthi16384e6:pieces20:01234567890123456789ee',
      ),
    );
    final torrent = await Torrent.parseFromBytes(bytes);
    final files = CacheEpisodeIndex.torrent(
      torrent,
      Directory.systemTemp.path,
      '动画',
      catalog,
    );
    expect(files.map((f) => f.episodeId), [101, 102, 0]);
    final task = DownloadTaskInfo(
      hash: 'hash',
      title: '动画 01-12',
      url: '',
      savePath: '',
      targetPath: files.first.path,
      bangumiSubjectId: 12,
      bangumiEpisodeId: 101,
      files: files,
    );
    const query = OnlineEpisodeQuery(
      bangumiSubjectId: 12,
      bangumiEpisodeId: 102,
      subjectTitle: '动画',
      aliases: [],
      episodeNumber: 2,
      episodeTitle: '雨',
    );
    final second = CachedMediaPlayback.episodeTasks(
      [task],
      query,
      previousPath: files.first.path,
    ).single;
    expect(second.targetPath, files[1].path);
  });
  test('首个入口返回其他种子时，核验备用入口并自动选中指定集', () async {
    final names = ['EP01.mkv', 'EP02.mkv'];
    final entries = names
        .map((n) => 'd6:lengthi1e4:pathl${n.length}:${n}ee')
        .join();
    final bytes = Uint8List.fromList(
      ascii.encode(
        'd4:infod5:filesl${entries}e4:name4:Pack12:piece lengthi16384e6:pieces20:01234567890123456789ee',
      ),
    );
    final expected = (await Torrent.parseFromBytes(bytes)).infoHash;
    final adapter = _TorrentEndpoints(bytes);
    final resolver = TorrentMediaResolver(
      client: Dio()..httpClientAdapter = adapter,
      directoryFor: (_) async => Directory.systemTemp,
    );
    final result = await resolver.prepareTask(
      'https://files.test/old',
      alternatives: ['https://files.test/backup'],
      expectedHash: expected,
      episodeLabel: '第 2 集',
    );
    expect(adapter.paths, ['/old', '/backup']);
    expect(result.uniquelyMatched, true);
    expect(result.taskInfo.episodeLabel, '第 2 集');
    expect(result.mediaInfo.fileName, 'EP02.mkv');
    await expectLater(
      resolver.prepareTask('https://files.test/old', expectedHash: expected),
      throwsFormatException,
    );
  });
  test('旧合集缺少 meta.torrent 时仍能从已完成的本地文件恢复每集', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('animemaster-pack-');
    final hash = 'A' * 40;
    final dir = await Directory('${root.path}/$hash').create();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = DownloadTaskRepository(db);
    final manager = DownloadManager.withDependencies(
      repo,
      (_, _, _) => throw StateError('unexpected transfer'),
    );
    try {
      final one = await File('${dir.path}/EP01.mkv').writeAsBytes([1]);
      final two = await File('${dir.path}/EP02.mkv').writeAsBytes([2, 2]);
      await repo.upsert(
        DownloadTaskInfo(
          hash: hash,
          title: '动画合集',
          subjectTitle: '动画',
          url: '',
          savePath: dir.path,
          targetPath: one.path,
          targetSize: 1,
          bangumiSubjectId: 12,
          bangumiEpisodeId: 101,
          isCompleted: true,
        ),
      );
      await manager.initPersistedTasks();
      final restored = manager.taskFor(hash)!;
      expect(restored.files.map((f) => f.number), unorderedEquals([1, 2]));
      const query = OnlineEpisodeQuery(
        subjectTitle: '动画',
        aliases: [],
        bangumiSubjectId: 12,
        bangumiEpisodeId: 102,
        episodeNumber: 2,
        episodeTitle: '',
      );
      final second = CachedMediaPlayback.episodeTasks(
        [restored],
        query,
        previousPath: one.path,
      ).single;
      expect(await second.hasCompleteFile(), true);
      expect(
        await File(second.targetPath).readAsBytes(),
        await two.readAsBytes(),
      );
    } finally {
      manager.dispose();
      await db.close();
      await root.delete(recursive: true);
    }
  });
  test('旧分 P 共用错误集号，重启后就地修复；人工校正和续播均保留', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('animemaster-legacy-');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = DownloadTaskRepository(db);
    DownloadManager manager() => DownloadManager.withDependencies(
      repo,
      (_, _, _) => throw StateError('unexpected transfer'),
    );
    for (final ep in catalog) {
      await db
          .into(db.animeEpisodes)
          .insert(
            AnimeEpisodesCompanion.insert(
              id: Value(ep['id'] as int),
              subjectId: 12,
              episodeNumber: Value(ep['ep'] as int),
              title: Value(ep['name'] as String),
            ),
          );
    }
    final originals = <File>[];
    for (final i in [1, 2]) {
      final folder = await Directory('${dir.path}/$i').create();
      final file = await File('${folder.path}/video.mp4').writeAsBytes([i]);
      originals.add(file);
      final task = DownloadTaskInfo(
        hash: 'bili_BV1xx411c7mD_$i',
        title: '动画全集 · P$i · 第 $i 集',
        url: '',
        savePath: folder.path,
        targetPath: file.path,
        targetSize: 1,
        subjectTitle: '动画',
        episodeLabel: '第 1 集',
        bangumiSubjectId: 12,
        bangumiEpisodeId: 101,
        isCompleted: true,
      );
      await repo.upsert(task);
      if (i == 2) {
        await db
            .into(db.playbackProgressRecords)
            .insert(
              PlaybackProgressRecordsCompanion.insert(
                mediaKey: PlaybackProgressStore.keyFor(
                  PlayableMedia(
                    title: '',
                    url: '',
                    bilibiliCacheIdentity: task.bilibiliIdentity,
                  ),
                ),
                bangumiSubjectId: const Value(12),
                bangumiEpisodeId: const Value(101),
                positionMs: const Value(34000),
              ),
            );
      }
    }
    var m = manager();
    try {
      await m.initPersistedTasks();
      expect(
        m.playableTasks.map((t) => t.bangumiEpisodeId),
        unorderedEquals([101, 102]),
      );
      expect(await repo.watchOfflineEpisode(12, 102, '').first, true);
      expect(
        (await db.select(db.playbackProgressRecords).getSingle())
            .bangumiEpisodeId,
        102,
      );
      final second = m.taskFor('bili_BV1xx411c7mD_2')!;
      await m.assignEpisode(second.hash, second.targetPath, 1);
      m.dispose();
      m = manager();
      await m.initPersistedTasks();
      final corrected = m.taskFor(second.hash)!;
      expect(corrected.files.single.manual, true);
      expect(corrected.bangumiEpisodeId, 101);
      expect(
        await repo.watchOfflineEpisode(12, 102, corrected.targetPath).first,
        false,
      );
      expect(
        (await db.select(db.playbackProgressRecords).getSingle()).positionMs,
        34000,
      );
      expect(await originals[0].readAsBytes(), [1]);
      expect(await originals[1].readAsBytes(), [2]);
    } finally {
      m.dispose();
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}

class _TorrentEndpoints implements HttpClientAdapter {
  _TorrentEndpoints(this.right);
  final Uint8List right;
  final paths = <String>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? request,
    Future<void>? cancel,
  ) async {
    paths.add(options.uri.path);
    final bytes = options.uri.path == '/old'
        ? ascii.encode(
            'd4:infod6:lengthi1e4:name8:test.mp412:piece lengthi16384e6:pieces20:abcdefghijklmnopqrstee',
          )
        : right;
    return ResponseBody.fromBytes(bytes, 200);
  }

  @override
  void close({bool force = false}) {}
}

import 'dart:io';

import 'package:animemaster/src/models/online_episode_source.dart';
import 'package:animemaster/src/repositories/bilibili_episode_mapping_repository.dart';
import 'package:animemaster/src/storage/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _VersionOneDatabase extends AppDatabase {
  _VersionOneDatabase(super.executor) : super.forTesting();
  @override
  int get schemaVersion => 1;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createTable(animeSubjects);
      await m.createTable(animeEpisodes);
      await m.createTable(downloadTaskRecords);
      await m.createTable(playbackProgressRecords);
    },
  );
}

const query = OnlineEpisodeQuery(
  bangumiSubjectId: 1,
  bangumiEpisodeId: 101,
  subjectTitle: '动画',
  aliases: <String>[],
  episodeNumber: 1,
  episodeTitle: '第一话',
);

void main() {
  test('manual mapping is saved by episode ID and can be replaced', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = BilibiliEpisodeMappingRepository(database: database);
    await repository.save(query, bvid: 'BV1xx411c7mD', cid: 100);
    expect((await repository.find(query))!.cid, 100);
    await repository.save(query, bvid: 'BV1yspC6sEne', cid: 200);
    expect((await repository.find(query))!.bvid, 'BV1yspC6sEne');
    expect(
      await database.select(database.bilibiliEpisodeMappings).get(),
      hasLength(1),
    );
  });

  test(
    'schema upgrade preserves existing playback progress and creates mappings',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bilibili-migration-',
      );
      final file = File('${directory.path}/test.sqlite');
      final previous = _VersionOneDatabase(NativeDatabase(file));
      await previous
          .into(previous.playbackProgressRecords)
          .insert(
            PlaybackProgressRecordsCompanion.insert(
              mediaKey: 'existing',
              title: const Value('已保存的视频'),
              positionMs: const Value(60000),
            ),
          );
      await previous.close();
      final current = AppDatabase.forTesting(NativeDatabase(file));
      try {
        final progress = await current
            .select(current.playbackProgressRecords)
            .getSingle();
        expect(progress.title, '已保存的视频');
        expect(progress.positionMs, 60000);
        final repository = BilibiliEpisodeMappingRepository(database: current);
        await repository.save(query, bvid: 'BV1xx411c7mD', cid: 100);
        expect((await repository.find(query))!.cid, 100);
      } finally {
        await current.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

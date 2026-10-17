import '../models/online_episode_source.dart';
import '../storage/app_database.dart';

class BilibiliEpisodeMappingRepository {
  BilibiliEpisodeMappingRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;
  static final BilibiliEpisodeMappingRepository instance =
      BilibiliEpisodeMappingRepository();
  final AppDatabase _database;

  static String? keyFor(OnlineEpisodeQuery query) {
    if (query.bangumiEpisodeId > 0) return 'episode:${query.bangumiEpisodeId}';
    if (query.bangumiSubjectId > 0 && query.episodeNumber > 0) {
      return 'subject:${query.bangumiSubjectId}:episode:${query.episodeNumber}';
    }
    return null;
  }

  Future<BilibiliEpisodeMapping?> find(OnlineEpisodeQuery query) async {
    final String? key = keyFor(query);
    if (key == null) return null;
    return (_database.select(
      _database.bilibiliEpisodeMappings,
    )..where((table) => table.mappingKey.equals(key))).getSingleOrNull();
  }

  Future<void> save(
    OnlineEpisodeQuery query, {
    required String bvid,
    required int cid,
  }) async {
    final String? key = keyFor(query);
    if (key == null || cid <= 0) return;
    await _database
        .into(_database.bilibiliEpisodeMappings)
        .insertOnConflictUpdate(
          BilibiliEpisodeMappingsCompanion.insert(
            mappingKey: key,
            bvid: bvid,
            cid: cid,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }
}

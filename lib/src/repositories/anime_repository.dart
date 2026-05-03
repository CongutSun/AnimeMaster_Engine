import 'package:drift/drift.dart';

import '../storage/app_database.dart';
import '../utils/episode_helpers.dart';

class AnimeRepository {
  AnimeRepository._(this._database);

  static final AnimeRepository instance = AnimeRepository._(
    AppDatabase.instance,
  );

  final AppDatabase _database;

  Future<Map<String, dynamic>?> loadSubject(int subjectId) async {
    final AnimeSubject? subject =
        await (_database.select(_database.animeSubjects)
              ..where((AnimeSubjects table) => table.id.equals(subjectId)))
            .getSingleOrNull();
    if (subject == null) {
      return null;
    }
    return <String, dynamic>{
      'id': subject.id,
      'name': subject.name,
      'name_cn': subject.nameCn,
      'eps': subject.episodeCount,
      'rating': <String, dynamic>{'score': subject.score},
      'images': <String, dynamic>{'large': subject.imageUrl},
    };
  }

  Future<List<Map<String, dynamic>>> loadEpisodes(int subjectId) async {
    final List<AnimeEpisode> rows =
        await (_database.select(_database.animeEpisodes)
              ..where(
                (AnimeEpisodes table) => table.subjectId.equals(subjectId),
              )
              ..orderBy(<OrderingTerm Function(AnimeEpisodes)>[
                (AnimeEpisodes table) => OrderingTerm.asc(table.episodeNumber),
                (AnimeEpisodes table) => OrderingTerm.asc(table.id),
              ]))
            .get();
    return rows.map(_episodeToJson).toList(growable: false);
  }

  Future<void> upsertSubject(Map<String, dynamic> data) async {
    final int id = int.tryParse(data['id']?.toString() ?? '') ?? 0;
    if (id <= 0) {
      return;
    }
    final Object? images = data['images'];
    final Map<dynamic, dynamic> imageMap = images is Map
        ? images
        : <dynamic, dynamic>{};
    final Object? rating = data['rating'];
    final Map<dynamic, dynamic> ratingMap = rating is Map
        ? rating
        : <dynamic, dynamic>{};

    await _database
        .into(_database.animeSubjects)
        .insertOnConflictUpdate(
          AnimeSubjectsCompanion.insert(
            id: Value(id),
            name: Value(data['name']?.toString() ?? ''),
            nameCn: Value(data['name_cn']?.toString() ?? ''),
            imageUrl: Value(imageMap['large']?.toString() ?? ''),
            score: Value(ratingMap['score']?.toString() ?? ''),
            episodeCount: Value(safeInt(data['eps'] ?? data['eps_count'])),
            updatedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  Future<void> upsertEpisodes(
    int subjectId,
    Iterable<Map<String, dynamic>> episodes,
  ) async {
    if (subjectId <= 0) {
      return;
    }
    final int updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    final List<AnimeEpisodesCompanion> rows = episodes
        .map((Map<String, dynamic> episode) {
          final int id = safeInt(episode['id']);
          if (id <= 0) {
            return null;
          }
          return AnimeEpisodesCompanion.insert(
            id: Value(id),
            subjectId: subjectId,
            episodeNumber: Value(safeInt(episode['ep'] ?? episode['sort'])),
            title: Value(episode['name']?.toString() ?? ''),
            titleCn: Value(episode['name_cn']?.toString() ?? ''),
            updatedAtMs: Value(updatedAtMs),
          );
        })
        .whereType<AnimeEpisodesCompanion>()
        .toList(growable: false);
    if (rows.isEmpty) {
      return;
    }

    await _database.batch((Batch batch) {
      batch.insertAllOnConflictUpdate(_database.animeEpisodes, rows);
    });
  }

  Future<void> markWatchedThrough({
    required int subjectId,
    required int episodeNumber,
  }) async {
    if (subjectId <= 0 || episodeNumber <= 0) {
      return;
    }
    final int updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    await (_database.update(_database.animeEpisodes)..where(
          (AnimeEpisodes table) =>
              table.subjectId.equals(subjectId) &
              table.episodeNumber.isSmallerOrEqualValue(episodeNumber),
        ))
        .write(
          AnimeEpisodesCompanion(
            isWatched: const Value(true),
            updatedAtMs: Value(updatedAtMs),
          ),
        );
  }

  Map<String, dynamic> _episodeToJson(AnimeEpisode row) {
    return <String, dynamic>{
      'id': row.id,
      'subject_id': row.subjectId,
      'ep': row.episodeNumber,
      'sort': row.episodeNumber,
      'name': row.title,
      'name_cn': row.titleCn,
      'watched_position_ms': row.watchedPositionMs,
      'duration_ms': row.durationMs,
      'is_watched': row.isWatched,
    };
  }

}

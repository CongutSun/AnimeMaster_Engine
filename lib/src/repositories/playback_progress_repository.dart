import 'package:drift/drift.dart';

import '../models/playable_media.dart';
import '../storage/app_database.dart';

class PlaybackProgressRepository {
  PlaybackProgressRepository._(this._database);

  static final PlaybackProgressRepository instance =
      PlaybackProgressRepository._(AppDatabase.instance);

  final AppDatabase _database;

  Future<PlaybackProgressRecord?> loadByKey(String mediaKey) {
    return (_database.select(_database.playbackProgressRecords)..where(
          (PlaybackProgressRecords table) => table.mediaKey.equals(mediaKey),
        ))
        .getSingleOrNull();
  }

  Future<void> save({
    required String mediaKey,
    required PlayableMedia media,
    required Duration position,
    required Duration duration,
  }) async {
    final int updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await _database
          .into(_database.playbackProgressRecords)
          .insertOnConflictUpdate(
            PlaybackProgressRecordsCompanion.insert(
              mediaKey: mediaKey,
              bangumiSubjectId: Value(media.bangumiSubjectId),
              bangumiEpisodeId: Value(media.bangumiEpisodeId),
              title: Value(media.title),
              subjectTitle: Value(media.subjectTitle),
              episodeLabel: Value(media.episodeLabel),
              localFilePath: Value(media.localFilePath),
              url: Value(media.url),
              positionMs: Value(position.inMilliseconds),
              durationMs: Value(duration.inMilliseconds),
              updatedAtMs: Value(updatedAtMs),
            ),
          );
      if (media.bangumiEpisodeId > 0) {
        await (_database.update(_database.animeEpisodes)..where(
              (AnimeEpisodes table) => table.id.equals(media.bangumiEpisodeId),
            ))
            .write(
              AnimeEpisodesCompanion(
                watchedPositionMs: Value(position.inMilliseconds),
                durationMs: Value(duration.inMilliseconds),
                isWatched: Value(
                  duration.inMilliseconds > 0 &&
                      position.inMilliseconds >=
                          duration.inMilliseconds - 20 * 1000,
                ),
                updatedAtMs: Value(updatedAtMs),
              ),
            );
      }
    });
  }
}

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class AnimeSubjects extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get nameCn => text().withDefault(const Constant(''))();
  TextColumn get imageUrl => text().withDefault(const Constant(''))();
  TextColumn get score => text().withDefault(const Constant(''))();
  IntColumn get episodeCount => integer().withDefault(const Constant(0))();
  IntColumn get updatedAtMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class AnimeEpisodes extends Table {
  IntColumn get id => integer()();
  IntColumn get subjectId => integer()();
  IntColumn get episodeNumber => integer().withDefault(const Constant(0))();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get titleCn => text().withDefault(const Constant(''))();
  IntColumn get watchedPositionMs => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  BoolColumn get isWatched => boolean().withDefault(const Constant(false))();
  IntColumn get updatedAtMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class DownloadTaskRecords extends Table {
  TextColumn get hash => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get url => text().withDefault(const Constant(''))();
  TextColumn get savePath => text().withDefault(const Constant(''))();
  TextColumn get targetPath => text().withDefault(const Constant(''))();
  IntColumn get targetSize => integer().withDefault(const Constant(0))();
  TextColumn get subjectTitle => text().withDefault(const Constant(''))();
  TextColumn get episodeLabel => text().withDefault(const Constant(''))();
  IntColumn get bangumiSubjectId => integer().withDefault(const Constant(0))();
  IntColumn get bangumiEpisodeId => integer().withDefault(const Constant(0))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  BoolColumn get isPaused => boolean().withDefault(const Constant(false))();
  IntColumn get updatedAtMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{hash};
}

class PlaybackProgressRecords extends Table {
  TextColumn get mediaKey => text()();
  IntColumn get bangumiSubjectId => integer().withDefault(const Constant(0))();
  IntColumn get bangumiEpisodeId => integer().withDefault(const Constant(0))();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get subjectTitle => text().withDefault(const Constant(''))();
  TextColumn get episodeLabel => text().withDefault(const Constant(''))();
  TextColumn get localFilePath => text().withDefault(const Constant(''))();
  TextColumn get url => text().withDefault(const Constant(''))();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  IntColumn get updatedAtMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{mediaKey};
}

@DriftDatabase(
  tables: <Type>[
    AnimeSubjects,
    AnimeEpisodes,
    DownloadTaskRecords,
    PlaybackProgressRecords,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._() : super(_openConnection());

  static final AppDatabase instance = AppDatabase._();

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final Directory directory = await getApplicationSupportDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final File file = File(
      '${directory.path}${Platform.pathSeparator}animemaster.sqlite',
    );
    return NativeDatabase.createInBackground(file);
  });
}

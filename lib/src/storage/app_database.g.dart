// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $AnimeSubjectsTable extends AnimeSubjects
    with TableInfo<$AnimeSubjectsTable, AnimeSubject> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AnimeSubjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameCnMeta = const VerificationMeta('nameCn');
  @override
  late final GeneratedColumn<String> nameCn = GeneratedColumn<String>(
    'name_cn',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _imageUrlMeta = const VerificationMeta(
    'imageUrl',
  );
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
    'image_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<String> score = GeneratedColumn<String>(
    'score',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _episodeCountMeta = const VerificationMeta(
    'episodeCount',
  );
  @override
  late final GeneratedColumn<int> episodeCount = GeneratedColumn<int>(
    'episode_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    nameCn,
    imageUrl,
    score,
    episodeCount,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'anime_subjects';
  @override
  VerificationContext validateIntegrity(
    Insertable<AnimeSubject> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('name_cn')) {
      context.handle(
        _nameCnMeta,
        nameCn.isAcceptableOrUnknown(data['name_cn']!, _nameCnMeta),
      );
    }
    if (data.containsKey('image_url')) {
      context.handle(
        _imageUrlMeta,
        imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta),
      );
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    }
    if (data.containsKey('episode_count')) {
      context.handle(
        _episodeCountMeta,
        episodeCount.isAcceptableOrUnknown(
          data['episode_count']!,
          _episodeCountMeta,
        ),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AnimeSubject map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AnimeSubject(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameCn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_cn'],
      )!,
      imageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_url'],
      )!,
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}score'],
      )!,
      episodeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode_count'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $AnimeSubjectsTable createAlias(String alias) {
    return $AnimeSubjectsTable(attachedDatabase, alias);
  }
}

class AnimeSubject extends DataClass implements Insertable<AnimeSubject> {
  final int id;
  final String name;
  final String nameCn;
  final String imageUrl;
  final String score;
  final int episodeCount;
  final int updatedAtMs;
  const AnimeSubject({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.imageUrl,
    required this.score,
    required this.episodeCount,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['name_cn'] = Variable<String>(nameCn);
    map['image_url'] = Variable<String>(imageUrl);
    map['score'] = Variable<String>(score);
    map['episode_count'] = Variable<int>(episodeCount);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  AnimeSubjectsCompanion toCompanion(bool nullToAbsent) {
    return AnimeSubjectsCompanion(
      id: Value(id),
      name: Value(name),
      nameCn: Value(nameCn),
      imageUrl: Value(imageUrl),
      score: Value(score),
      episodeCount: Value(episodeCount),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory AnimeSubject.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AnimeSubject(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      nameCn: serializer.fromJson<String>(json['nameCn']),
      imageUrl: serializer.fromJson<String>(json['imageUrl']),
      score: serializer.fromJson<String>(json['score']),
      episodeCount: serializer.fromJson<int>(json['episodeCount']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'nameCn': serializer.toJson<String>(nameCn),
      'imageUrl': serializer.toJson<String>(imageUrl),
      'score': serializer.toJson<String>(score),
      'episodeCount': serializer.toJson<int>(episodeCount),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  AnimeSubject copyWith({
    int? id,
    String? name,
    String? nameCn,
    String? imageUrl,
    String? score,
    int? episodeCount,
    int? updatedAtMs,
  }) => AnimeSubject(
    id: id ?? this.id,
    name: name ?? this.name,
    nameCn: nameCn ?? this.nameCn,
    imageUrl: imageUrl ?? this.imageUrl,
    score: score ?? this.score,
    episodeCount: episodeCount ?? this.episodeCount,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  AnimeSubject copyWithCompanion(AnimeSubjectsCompanion data) {
    return AnimeSubject(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      nameCn: data.nameCn.present ? data.nameCn.value : this.nameCn,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      score: data.score.present ? data.score.value : this.score,
      episodeCount: data.episodeCount.present
          ? data.episodeCount.value
          : this.episodeCount,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AnimeSubject(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameCn: $nameCn, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('score: $score, ')
          ..write('episodeCount: $episodeCount, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, nameCn, imageUrl, score, episodeCount, updatedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AnimeSubject &&
          other.id == this.id &&
          other.name == this.name &&
          other.nameCn == this.nameCn &&
          other.imageUrl == this.imageUrl &&
          other.score == this.score &&
          other.episodeCount == this.episodeCount &&
          other.updatedAtMs == this.updatedAtMs);
}

class AnimeSubjectsCompanion extends UpdateCompanion<AnimeSubject> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> nameCn;
  final Value<String> imageUrl;
  final Value<String> score;
  final Value<int> episodeCount;
  final Value<int> updatedAtMs;
  const AnimeSubjectsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameCn = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.score = const Value.absent(),
    this.episodeCount = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
  });
  AnimeSubjectsCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameCn = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.score = const Value.absent(),
    this.episodeCount = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
  });
  static Insertable<AnimeSubject> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? nameCn,
    Expression<String>? imageUrl,
    Expression<String>? score,
    Expression<int>? episodeCount,
    Expression<int>? updatedAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (nameCn != null) 'name_cn': nameCn,
      if (imageUrl != null) 'image_url': imageUrl,
      if (score != null) 'score': score,
      if (episodeCount != null) 'episode_count': episodeCount,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
    });
  }

  AnimeSubjectsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? nameCn,
    Value<String>? imageUrl,
    Value<String>? score,
    Value<int>? episodeCount,
    Value<int>? updatedAtMs,
  }) {
    return AnimeSubjectsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      nameCn: nameCn ?? this.nameCn,
      imageUrl: imageUrl ?? this.imageUrl,
      score: score ?? this.score,
      episodeCount: episodeCount ?? this.episodeCount,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameCn.present) {
      map['name_cn'] = Variable<String>(nameCn.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (score.present) {
      map['score'] = Variable<String>(score.value);
    }
    if (episodeCount.present) {
      map['episode_count'] = Variable<int>(episodeCount.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AnimeSubjectsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameCn: $nameCn, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('score: $score, ')
          ..write('episodeCount: $episodeCount, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }
}

class $AnimeEpisodesTable extends AnimeEpisodes
    with TableInfo<$AnimeEpisodesTable, AnimeEpisode> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AnimeEpisodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subjectIdMeta = const VerificationMeta(
    'subjectId',
  );
  @override
  late final GeneratedColumn<int> subjectId = GeneratedColumn<int>(
    'subject_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _episodeNumberMeta = const VerificationMeta(
    'episodeNumber',
  );
  @override
  late final GeneratedColumn<int> episodeNumber = GeneratedColumn<int>(
    'episode_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _titleCnMeta = const VerificationMeta(
    'titleCn',
  );
  @override
  late final GeneratedColumn<String> titleCn = GeneratedColumn<String>(
    'title_cn',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _watchedPositionMsMeta = const VerificationMeta(
    'watchedPositionMs',
  );
  @override
  late final GeneratedColumn<int> watchedPositionMs = GeneratedColumn<int>(
    'watched_position_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isWatchedMeta = const VerificationMeta(
    'isWatched',
  );
  @override
  late final GeneratedColumn<bool> isWatched = GeneratedColumn<bool>(
    'is_watched',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_watched" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    subjectId,
    episodeNumber,
    title,
    titleCn,
    watchedPositionMs,
    durationMs,
    isWatched,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'anime_episodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<AnimeEpisode> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('subject_id')) {
      context.handle(
        _subjectIdMeta,
        subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    if (data.containsKey('episode_number')) {
      context.handle(
        _episodeNumberMeta,
        episodeNumber.isAcceptableOrUnknown(
          data['episode_number']!,
          _episodeNumberMeta,
        ),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('title_cn')) {
      context.handle(
        _titleCnMeta,
        titleCn.isAcceptableOrUnknown(data['title_cn']!, _titleCnMeta),
      );
    }
    if (data.containsKey('watched_position_ms')) {
      context.handle(
        _watchedPositionMsMeta,
        watchedPositionMs.isAcceptableOrUnknown(
          data['watched_position_ms']!,
          _watchedPositionMsMeta,
        ),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('is_watched')) {
      context.handle(
        _isWatchedMeta,
        isWatched.isAcceptableOrUnknown(data['is_watched']!, _isWatchedMeta),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AnimeEpisode map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AnimeEpisode(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      subjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}subject_id'],
      )!,
      episodeNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode_number'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      titleCn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_cn'],
      )!,
      watchedPositionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}watched_position_ms'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      isWatched: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_watched'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $AnimeEpisodesTable createAlias(String alias) {
    return $AnimeEpisodesTable(attachedDatabase, alias);
  }
}

class AnimeEpisode extends DataClass implements Insertable<AnimeEpisode> {
  final int id;
  final int subjectId;
  final int episodeNumber;
  final String title;
  final String titleCn;
  final int watchedPositionMs;
  final int durationMs;
  final bool isWatched;
  final int updatedAtMs;
  const AnimeEpisode({
    required this.id,
    required this.subjectId,
    required this.episodeNumber,
    required this.title,
    required this.titleCn,
    required this.watchedPositionMs,
    required this.durationMs,
    required this.isWatched,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['subject_id'] = Variable<int>(subjectId);
    map['episode_number'] = Variable<int>(episodeNumber);
    map['title'] = Variable<String>(title);
    map['title_cn'] = Variable<String>(titleCn);
    map['watched_position_ms'] = Variable<int>(watchedPositionMs);
    map['duration_ms'] = Variable<int>(durationMs);
    map['is_watched'] = Variable<bool>(isWatched);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  AnimeEpisodesCompanion toCompanion(bool nullToAbsent) {
    return AnimeEpisodesCompanion(
      id: Value(id),
      subjectId: Value(subjectId),
      episodeNumber: Value(episodeNumber),
      title: Value(title),
      titleCn: Value(titleCn),
      watchedPositionMs: Value(watchedPositionMs),
      durationMs: Value(durationMs),
      isWatched: Value(isWatched),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory AnimeEpisode.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AnimeEpisode(
      id: serializer.fromJson<int>(json['id']),
      subjectId: serializer.fromJson<int>(json['subjectId']),
      episodeNumber: serializer.fromJson<int>(json['episodeNumber']),
      title: serializer.fromJson<String>(json['title']),
      titleCn: serializer.fromJson<String>(json['titleCn']),
      watchedPositionMs: serializer.fromJson<int>(json['watchedPositionMs']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      isWatched: serializer.fromJson<bool>(json['isWatched']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'subjectId': serializer.toJson<int>(subjectId),
      'episodeNumber': serializer.toJson<int>(episodeNumber),
      'title': serializer.toJson<String>(title),
      'titleCn': serializer.toJson<String>(titleCn),
      'watchedPositionMs': serializer.toJson<int>(watchedPositionMs),
      'durationMs': serializer.toJson<int>(durationMs),
      'isWatched': serializer.toJson<bool>(isWatched),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  AnimeEpisode copyWith({
    int? id,
    int? subjectId,
    int? episodeNumber,
    String? title,
    String? titleCn,
    int? watchedPositionMs,
    int? durationMs,
    bool? isWatched,
    int? updatedAtMs,
  }) => AnimeEpisode(
    id: id ?? this.id,
    subjectId: subjectId ?? this.subjectId,
    episodeNumber: episodeNumber ?? this.episodeNumber,
    title: title ?? this.title,
    titleCn: titleCn ?? this.titleCn,
    watchedPositionMs: watchedPositionMs ?? this.watchedPositionMs,
    durationMs: durationMs ?? this.durationMs,
    isWatched: isWatched ?? this.isWatched,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  AnimeEpisode copyWithCompanion(AnimeEpisodesCompanion data) {
    return AnimeEpisode(
      id: data.id.present ? data.id.value : this.id,
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      episodeNumber: data.episodeNumber.present
          ? data.episodeNumber.value
          : this.episodeNumber,
      title: data.title.present ? data.title.value : this.title,
      titleCn: data.titleCn.present ? data.titleCn.value : this.titleCn,
      watchedPositionMs: data.watchedPositionMs.present
          ? data.watchedPositionMs.value
          : this.watchedPositionMs,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      isWatched: data.isWatched.present ? data.isWatched.value : this.isWatched,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AnimeEpisode(')
          ..write('id: $id, ')
          ..write('subjectId: $subjectId, ')
          ..write('episodeNumber: $episodeNumber, ')
          ..write('title: $title, ')
          ..write('titleCn: $titleCn, ')
          ..write('watchedPositionMs: $watchedPositionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('isWatched: $isWatched, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    subjectId,
    episodeNumber,
    title,
    titleCn,
    watchedPositionMs,
    durationMs,
    isWatched,
    updatedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AnimeEpisode &&
          other.id == this.id &&
          other.subjectId == this.subjectId &&
          other.episodeNumber == this.episodeNumber &&
          other.title == this.title &&
          other.titleCn == this.titleCn &&
          other.watchedPositionMs == this.watchedPositionMs &&
          other.durationMs == this.durationMs &&
          other.isWatched == this.isWatched &&
          other.updatedAtMs == this.updatedAtMs);
}

class AnimeEpisodesCompanion extends UpdateCompanion<AnimeEpisode> {
  final Value<int> id;
  final Value<int> subjectId;
  final Value<int> episodeNumber;
  final Value<String> title;
  final Value<String> titleCn;
  final Value<int> watchedPositionMs;
  final Value<int> durationMs;
  final Value<bool> isWatched;
  final Value<int> updatedAtMs;
  const AnimeEpisodesCompanion({
    this.id = const Value.absent(),
    this.subjectId = const Value.absent(),
    this.episodeNumber = const Value.absent(),
    this.title = const Value.absent(),
    this.titleCn = const Value.absent(),
    this.watchedPositionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.isWatched = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
  });
  AnimeEpisodesCompanion.insert({
    this.id = const Value.absent(),
    required int subjectId,
    this.episodeNumber = const Value.absent(),
    this.title = const Value.absent(),
    this.titleCn = const Value.absent(),
    this.watchedPositionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.isWatched = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
  }) : subjectId = Value(subjectId);
  static Insertable<AnimeEpisode> custom({
    Expression<int>? id,
    Expression<int>? subjectId,
    Expression<int>? episodeNumber,
    Expression<String>? title,
    Expression<String>? titleCn,
    Expression<int>? watchedPositionMs,
    Expression<int>? durationMs,
    Expression<bool>? isWatched,
    Expression<int>? updatedAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (subjectId != null) 'subject_id': subjectId,
      if (episodeNumber != null) 'episode_number': episodeNumber,
      if (title != null) 'title': title,
      if (titleCn != null) 'title_cn': titleCn,
      if (watchedPositionMs != null) 'watched_position_ms': watchedPositionMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (isWatched != null) 'is_watched': isWatched,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
    });
  }

  AnimeEpisodesCompanion copyWith({
    Value<int>? id,
    Value<int>? subjectId,
    Value<int>? episodeNumber,
    Value<String>? title,
    Value<String>? titleCn,
    Value<int>? watchedPositionMs,
    Value<int>? durationMs,
    Value<bool>? isWatched,
    Value<int>? updatedAtMs,
  }) {
    return AnimeEpisodesCompanion(
      id: id ?? this.id,
      subjectId: subjectId ?? this.subjectId,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      title: title ?? this.title,
      titleCn: titleCn ?? this.titleCn,
      watchedPositionMs: watchedPositionMs ?? this.watchedPositionMs,
      durationMs: durationMs ?? this.durationMs,
      isWatched: isWatched ?? this.isWatched,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (subjectId.present) {
      map['subject_id'] = Variable<int>(subjectId.value);
    }
    if (episodeNumber.present) {
      map['episode_number'] = Variable<int>(episodeNumber.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (titleCn.present) {
      map['title_cn'] = Variable<String>(titleCn.value);
    }
    if (watchedPositionMs.present) {
      map['watched_position_ms'] = Variable<int>(watchedPositionMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (isWatched.present) {
      map['is_watched'] = Variable<bool>(isWatched.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AnimeEpisodesCompanion(')
          ..write('id: $id, ')
          ..write('subjectId: $subjectId, ')
          ..write('episodeNumber: $episodeNumber, ')
          ..write('title: $title, ')
          ..write('titleCn: $titleCn, ')
          ..write('watchedPositionMs: $watchedPositionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('isWatched: $isWatched, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }
}

class $DownloadTaskRecordsTable extends DownloadTaskRecords
    with TableInfo<$DownloadTaskRecordsTable, DownloadTaskRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadTaskRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _hashMeta = const VerificationMeta('hash');
  @override
  late final GeneratedColumn<String> hash = GeneratedColumn<String>(
    'hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _savePathMeta = const VerificationMeta(
    'savePath',
  );
  @override
  late final GeneratedColumn<String> savePath = GeneratedColumn<String>(
    'save_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _targetPathMeta = const VerificationMeta(
    'targetPath',
  );
  @override
  late final GeneratedColumn<String> targetPath = GeneratedColumn<String>(
    'target_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _targetSizeMeta = const VerificationMeta(
    'targetSize',
  );
  @override
  late final GeneratedColumn<int> targetSize = GeneratedColumn<int>(
    'target_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _subjectTitleMeta = const VerificationMeta(
    'subjectTitle',
  );
  @override
  late final GeneratedColumn<String> subjectTitle = GeneratedColumn<String>(
    'subject_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _episodeLabelMeta = const VerificationMeta(
    'episodeLabel',
  );
  @override
  late final GeneratedColumn<String> episodeLabel = GeneratedColumn<String>(
    'episode_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _bangumiSubjectIdMeta = const VerificationMeta(
    'bangumiSubjectId',
  );
  @override
  late final GeneratedColumn<int> bangumiSubjectId = GeneratedColumn<int>(
    'bangumi_subject_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _bangumiEpisodeIdMeta = const VerificationMeta(
    'bangumiEpisodeId',
  );
  @override
  late final GeneratedColumn<int> bangumiEpisodeId = GeneratedColumn<int>(
    'bangumi_episode_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isCompletedMeta = const VerificationMeta(
    'isCompleted',
  );
  @override
  late final GeneratedColumn<bool> isCompleted = GeneratedColumn<bool>(
    'is_completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_completed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isPausedMeta = const VerificationMeta(
    'isPaused',
  );
  @override
  late final GeneratedColumn<bool> isPaused = GeneratedColumn<bool>(
    'is_paused',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_paused" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    hash,
    title,
    url,
    savePath,
    targetPath,
    targetSize,
    subjectTitle,
    episodeLabel,
    bangumiSubjectId,
    bangumiEpisodeId,
    isCompleted,
    isPaused,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'download_task_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<DownloadTaskRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('hash')) {
      context.handle(
        _hashMeta,
        hash.isAcceptableOrUnknown(data['hash']!, _hashMeta),
      );
    } else if (isInserting) {
      context.missing(_hashMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    }
    if (data.containsKey('save_path')) {
      context.handle(
        _savePathMeta,
        savePath.isAcceptableOrUnknown(data['save_path']!, _savePathMeta),
      );
    }
    if (data.containsKey('target_path')) {
      context.handle(
        _targetPathMeta,
        targetPath.isAcceptableOrUnknown(data['target_path']!, _targetPathMeta),
      );
    }
    if (data.containsKey('target_size')) {
      context.handle(
        _targetSizeMeta,
        targetSize.isAcceptableOrUnknown(data['target_size']!, _targetSizeMeta),
      );
    }
    if (data.containsKey('subject_title')) {
      context.handle(
        _subjectTitleMeta,
        subjectTitle.isAcceptableOrUnknown(
          data['subject_title']!,
          _subjectTitleMeta,
        ),
      );
    }
    if (data.containsKey('episode_label')) {
      context.handle(
        _episodeLabelMeta,
        episodeLabel.isAcceptableOrUnknown(
          data['episode_label']!,
          _episodeLabelMeta,
        ),
      );
    }
    if (data.containsKey('bangumi_subject_id')) {
      context.handle(
        _bangumiSubjectIdMeta,
        bangumiSubjectId.isAcceptableOrUnknown(
          data['bangumi_subject_id']!,
          _bangumiSubjectIdMeta,
        ),
      );
    }
    if (data.containsKey('bangumi_episode_id')) {
      context.handle(
        _bangumiEpisodeIdMeta,
        bangumiEpisodeId.isAcceptableOrUnknown(
          data['bangumi_episode_id']!,
          _bangumiEpisodeIdMeta,
        ),
      );
    }
    if (data.containsKey('is_completed')) {
      context.handle(
        _isCompletedMeta,
        isCompleted.isAcceptableOrUnknown(
          data['is_completed']!,
          _isCompletedMeta,
        ),
      );
    }
    if (data.containsKey('is_paused')) {
      context.handle(
        _isPausedMeta,
        isPaused.isAcceptableOrUnknown(data['is_paused']!, _isPausedMeta),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {hash};
  @override
  DownloadTaskRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DownloadTaskRecord(
      hash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hash'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      savePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}save_path'],
      )!,
      targetPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_path'],
      )!,
      targetSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_size'],
      )!,
      subjectTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_title'],
      )!,
      episodeLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}episode_label'],
      )!,
      bangumiSubjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bangumi_subject_id'],
      )!,
      bangumiEpisodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bangumi_episode_id'],
      )!,
      isCompleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_completed'],
      )!,
      isPaused: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_paused'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $DownloadTaskRecordsTable createAlias(String alias) {
    return $DownloadTaskRecordsTable(attachedDatabase, alias);
  }
}

class DownloadTaskRecord extends DataClass
    implements Insertable<DownloadTaskRecord> {
  final String hash;
  final String title;
  final String url;
  final String savePath;
  final String targetPath;
  final int targetSize;
  final String subjectTitle;
  final String episodeLabel;
  final int bangumiSubjectId;
  final int bangumiEpisodeId;
  final bool isCompleted;
  final bool isPaused;
  final int updatedAtMs;
  const DownloadTaskRecord({
    required this.hash,
    required this.title,
    required this.url,
    required this.savePath,
    required this.targetPath,
    required this.targetSize,
    required this.subjectTitle,
    required this.episodeLabel,
    required this.bangumiSubjectId,
    required this.bangumiEpisodeId,
    required this.isCompleted,
    required this.isPaused,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['hash'] = Variable<String>(hash);
    map['title'] = Variable<String>(title);
    map['url'] = Variable<String>(url);
    map['save_path'] = Variable<String>(savePath);
    map['target_path'] = Variable<String>(targetPath);
    map['target_size'] = Variable<int>(targetSize);
    map['subject_title'] = Variable<String>(subjectTitle);
    map['episode_label'] = Variable<String>(episodeLabel);
    map['bangumi_subject_id'] = Variable<int>(bangumiSubjectId);
    map['bangumi_episode_id'] = Variable<int>(bangumiEpisodeId);
    map['is_completed'] = Variable<bool>(isCompleted);
    map['is_paused'] = Variable<bool>(isPaused);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  DownloadTaskRecordsCompanion toCompanion(bool nullToAbsent) {
    return DownloadTaskRecordsCompanion(
      hash: Value(hash),
      title: Value(title),
      url: Value(url),
      savePath: Value(savePath),
      targetPath: Value(targetPath),
      targetSize: Value(targetSize),
      subjectTitle: Value(subjectTitle),
      episodeLabel: Value(episodeLabel),
      bangumiSubjectId: Value(bangumiSubjectId),
      bangumiEpisodeId: Value(bangumiEpisodeId),
      isCompleted: Value(isCompleted),
      isPaused: Value(isPaused),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory DownloadTaskRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DownloadTaskRecord(
      hash: serializer.fromJson<String>(json['hash']),
      title: serializer.fromJson<String>(json['title']),
      url: serializer.fromJson<String>(json['url']),
      savePath: serializer.fromJson<String>(json['savePath']),
      targetPath: serializer.fromJson<String>(json['targetPath']),
      targetSize: serializer.fromJson<int>(json['targetSize']),
      subjectTitle: serializer.fromJson<String>(json['subjectTitle']),
      episodeLabel: serializer.fromJson<String>(json['episodeLabel']),
      bangumiSubjectId: serializer.fromJson<int>(json['bangumiSubjectId']),
      bangumiEpisodeId: serializer.fromJson<int>(json['bangumiEpisodeId']),
      isCompleted: serializer.fromJson<bool>(json['isCompleted']),
      isPaused: serializer.fromJson<bool>(json['isPaused']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'hash': serializer.toJson<String>(hash),
      'title': serializer.toJson<String>(title),
      'url': serializer.toJson<String>(url),
      'savePath': serializer.toJson<String>(savePath),
      'targetPath': serializer.toJson<String>(targetPath),
      'targetSize': serializer.toJson<int>(targetSize),
      'subjectTitle': serializer.toJson<String>(subjectTitle),
      'episodeLabel': serializer.toJson<String>(episodeLabel),
      'bangumiSubjectId': serializer.toJson<int>(bangumiSubjectId),
      'bangumiEpisodeId': serializer.toJson<int>(bangumiEpisodeId),
      'isCompleted': serializer.toJson<bool>(isCompleted),
      'isPaused': serializer.toJson<bool>(isPaused),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  DownloadTaskRecord copyWith({
    String? hash,
    String? title,
    String? url,
    String? savePath,
    String? targetPath,
    int? targetSize,
    String? subjectTitle,
    String? episodeLabel,
    int? bangumiSubjectId,
    int? bangumiEpisodeId,
    bool? isCompleted,
    bool? isPaused,
    int? updatedAtMs,
  }) => DownloadTaskRecord(
    hash: hash ?? this.hash,
    title: title ?? this.title,
    url: url ?? this.url,
    savePath: savePath ?? this.savePath,
    targetPath: targetPath ?? this.targetPath,
    targetSize: targetSize ?? this.targetSize,
    subjectTitle: subjectTitle ?? this.subjectTitle,
    episodeLabel: episodeLabel ?? this.episodeLabel,
    bangumiSubjectId: bangumiSubjectId ?? this.bangumiSubjectId,
    bangumiEpisodeId: bangumiEpisodeId ?? this.bangumiEpisodeId,
    isCompleted: isCompleted ?? this.isCompleted,
    isPaused: isPaused ?? this.isPaused,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  DownloadTaskRecord copyWithCompanion(DownloadTaskRecordsCompanion data) {
    return DownloadTaskRecord(
      hash: data.hash.present ? data.hash.value : this.hash,
      title: data.title.present ? data.title.value : this.title,
      url: data.url.present ? data.url.value : this.url,
      savePath: data.savePath.present ? data.savePath.value : this.savePath,
      targetPath: data.targetPath.present
          ? data.targetPath.value
          : this.targetPath,
      targetSize: data.targetSize.present
          ? data.targetSize.value
          : this.targetSize,
      subjectTitle: data.subjectTitle.present
          ? data.subjectTitle.value
          : this.subjectTitle,
      episodeLabel: data.episodeLabel.present
          ? data.episodeLabel.value
          : this.episodeLabel,
      bangumiSubjectId: data.bangumiSubjectId.present
          ? data.bangumiSubjectId.value
          : this.bangumiSubjectId,
      bangumiEpisodeId: data.bangumiEpisodeId.present
          ? data.bangumiEpisodeId.value
          : this.bangumiEpisodeId,
      isCompleted: data.isCompleted.present
          ? data.isCompleted.value
          : this.isCompleted,
      isPaused: data.isPaused.present ? data.isPaused.value : this.isPaused,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DownloadTaskRecord(')
          ..write('hash: $hash, ')
          ..write('title: $title, ')
          ..write('url: $url, ')
          ..write('savePath: $savePath, ')
          ..write('targetPath: $targetPath, ')
          ..write('targetSize: $targetSize, ')
          ..write('subjectTitle: $subjectTitle, ')
          ..write('episodeLabel: $episodeLabel, ')
          ..write('bangumiSubjectId: $bangumiSubjectId, ')
          ..write('bangumiEpisodeId: $bangumiEpisodeId, ')
          ..write('isCompleted: $isCompleted, ')
          ..write('isPaused: $isPaused, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    hash,
    title,
    url,
    savePath,
    targetPath,
    targetSize,
    subjectTitle,
    episodeLabel,
    bangumiSubjectId,
    bangumiEpisodeId,
    isCompleted,
    isPaused,
    updatedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DownloadTaskRecord &&
          other.hash == this.hash &&
          other.title == this.title &&
          other.url == this.url &&
          other.savePath == this.savePath &&
          other.targetPath == this.targetPath &&
          other.targetSize == this.targetSize &&
          other.subjectTitle == this.subjectTitle &&
          other.episodeLabel == this.episodeLabel &&
          other.bangumiSubjectId == this.bangumiSubjectId &&
          other.bangumiEpisodeId == this.bangumiEpisodeId &&
          other.isCompleted == this.isCompleted &&
          other.isPaused == this.isPaused &&
          other.updatedAtMs == this.updatedAtMs);
}

class DownloadTaskRecordsCompanion extends UpdateCompanion<DownloadTaskRecord> {
  final Value<String> hash;
  final Value<String> title;
  final Value<String> url;
  final Value<String> savePath;
  final Value<String> targetPath;
  final Value<int> targetSize;
  final Value<String> subjectTitle;
  final Value<String> episodeLabel;
  final Value<int> bangumiSubjectId;
  final Value<int> bangumiEpisodeId;
  final Value<bool> isCompleted;
  final Value<bool> isPaused;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const DownloadTaskRecordsCompanion({
    this.hash = const Value.absent(),
    this.title = const Value.absent(),
    this.url = const Value.absent(),
    this.savePath = const Value.absent(),
    this.targetPath = const Value.absent(),
    this.targetSize = const Value.absent(),
    this.subjectTitle = const Value.absent(),
    this.episodeLabel = const Value.absent(),
    this.bangumiSubjectId = const Value.absent(),
    this.bangumiEpisodeId = const Value.absent(),
    this.isCompleted = const Value.absent(),
    this.isPaused = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DownloadTaskRecordsCompanion.insert({
    required String hash,
    this.title = const Value.absent(),
    this.url = const Value.absent(),
    this.savePath = const Value.absent(),
    this.targetPath = const Value.absent(),
    this.targetSize = const Value.absent(),
    this.subjectTitle = const Value.absent(),
    this.episodeLabel = const Value.absent(),
    this.bangumiSubjectId = const Value.absent(),
    this.bangumiEpisodeId = const Value.absent(),
    this.isCompleted = const Value.absent(),
    this.isPaused = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : hash = Value(hash);
  static Insertable<DownloadTaskRecord> custom({
    Expression<String>? hash,
    Expression<String>? title,
    Expression<String>? url,
    Expression<String>? savePath,
    Expression<String>? targetPath,
    Expression<int>? targetSize,
    Expression<String>? subjectTitle,
    Expression<String>? episodeLabel,
    Expression<int>? bangumiSubjectId,
    Expression<int>? bangumiEpisodeId,
    Expression<bool>? isCompleted,
    Expression<bool>? isPaused,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (hash != null) 'hash': hash,
      if (title != null) 'title': title,
      if (url != null) 'url': url,
      if (savePath != null) 'save_path': savePath,
      if (targetPath != null) 'target_path': targetPath,
      if (targetSize != null) 'target_size': targetSize,
      if (subjectTitle != null) 'subject_title': subjectTitle,
      if (episodeLabel != null) 'episode_label': episodeLabel,
      if (bangumiSubjectId != null) 'bangumi_subject_id': bangumiSubjectId,
      if (bangumiEpisodeId != null) 'bangumi_episode_id': bangumiEpisodeId,
      if (isCompleted != null) 'is_completed': isCompleted,
      if (isPaused != null) 'is_paused': isPaused,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DownloadTaskRecordsCompanion copyWith({
    Value<String>? hash,
    Value<String>? title,
    Value<String>? url,
    Value<String>? savePath,
    Value<String>? targetPath,
    Value<int>? targetSize,
    Value<String>? subjectTitle,
    Value<String>? episodeLabel,
    Value<int>? bangumiSubjectId,
    Value<int>? bangumiEpisodeId,
    Value<bool>? isCompleted,
    Value<bool>? isPaused,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return DownloadTaskRecordsCompanion(
      hash: hash ?? this.hash,
      title: title ?? this.title,
      url: url ?? this.url,
      savePath: savePath ?? this.savePath,
      targetPath: targetPath ?? this.targetPath,
      targetSize: targetSize ?? this.targetSize,
      subjectTitle: subjectTitle ?? this.subjectTitle,
      episodeLabel: episodeLabel ?? this.episodeLabel,
      bangumiSubjectId: bangumiSubjectId ?? this.bangumiSubjectId,
      bangumiEpisodeId: bangumiEpisodeId ?? this.bangumiEpisodeId,
      isCompleted: isCompleted ?? this.isCompleted,
      isPaused: isPaused ?? this.isPaused,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (hash.present) {
      map['hash'] = Variable<String>(hash.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (savePath.present) {
      map['save_path'] = Variable<String>(savePath.value);
    }
    if (targetPath.present) {
      map['target_path'] = Variable<String>(targetPath.value);
    }
    if (targetSize.present) {
      map['target_size'] = Variable<int>(targetSize.value);
    }
    if (subjectTitle.present) {
      map['subject_title'] = Variable<String>(subjectTitle.value);
    }
    if (episodeLabel.present) {
      map['episode_label'] = Variable<String>(episodeLabel.value);
    }
    if (bangumiSubjectId.present) {
      map['bangumi_subject_id'] = Variable<int>(bangumiSubjectId.value);
    }
    if (bangumiEpisodeId.present) {
      map['bangumi_episode_id'] = Variable<int>(bangumiEpisodeId.value);
    }
    if (isCompleted.present) {
      map['is_completed'] = Variable<bool>(isCompleted.value);
    }
    if (isPaused.present) {
      map['is_paused'] = Variable<bool>(isPaused.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadTaskRecordsCompanion(')
          ..write('hash: $hash, ')
          ..write('title: $title, ')
          ..write('url: $url, ')
          ..write('savePath: $savePath, ')
          ..write('targetPath: $targetPath, ')
          ..write('targetSize: $targetSize, ')
          ..write('subjectTitle: $subjectTitle, ')
          ..write('episodeLabel: $episodeLabel, ')
          ..write('bangumiSubjectId: $bangumiSubjectId, ')
          ..write('bangumiEpisodeId: $bangumiEpisodeId, ')
          ..write('isCompleted: $isCompleted, ')
          ..write('isPaused: $isPaused, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaybackProgressRecordsTable extends PlaybackProgressRecords
    with TableInfo<$PlaybackProgressRecordsTable, PlaybackProgressRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaybackProgressRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaKeyMeta = const VerificationMeta(
    'mediaKey',
  );
  @override
  late final GeneratedColumn<String> mediaKey = GeneratedColumn<String>(
    'media_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bangumiSubjectIdMeta = const VerificationMeta(
    'bangumiSubjectId',
  );
  @override
  late final GeneratedColumn<int> bangumiSubjectId = GeneratedColumn<int>(
    'bangumi_subject_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _bangumiEpisodeIdMeta = const VerificationMeta(
    'bangumiEpisodeId',
  );
  @override
  late final GeneratedColumn<int> bangumiEpisodeId = GeneratedColumn<int>(
    'bangumi_episode_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _subjectTitleMeta = const VerificationMeta(
    'subjectTitle',
  );
  @override
  late final GeneratedColumn<String> subjectTitle = GeneratedColumn<String>(
    'subject_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _episodeLabelMeta = const VerificationMeta(
    'episodeLabel',
  );
  @override
  late final GeneratedColumn<String> episodeLabel = GeneratedColumn<String>(
    'episode_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _localFilePathMeta = const VerificationMeta(
    'localFilePath',
  );
  @override
  late final GeneratedColumn<String> localFilePath = GeneratedColumn<String>(
    'local_file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _positionMsMeta = const VerificationMeta(
    'positionMs',
  );
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
    'position_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    mediaKey,
    bangumiSubjectId,
    bangumiEpisodeId,
    title,
    subjectTitle,
    episodeLabel,
    localFilePath,
    url,
    positionMs,
    durationMs,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playback_progress_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaybackProgressRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('media_key')) {
      context.handle(
        _mediaKeyMeta,
        mediaKey.isAcceptableOrUnknown(data['media_key']!, _mediaKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaKeyMeta);
    }
    if (data.containsKey('bangumi_subject_id')) {
      context.handle(
        _bangumiSubjectIdMeta,
        bangumiSubjectId.isAcceptableOrUnknown(
          data['bangumi_subject_id']!,
          _bangumiSubjectIdMeta,
        ),
      );
    }
    if (data.containsKey('bangumi_episode_id')) {
      context.handle(
        _bangumiEpisodeIdMeta,
        bangumiEpisodeId.isAcceptableOrUnknown(
          data['bangumi_episode_id']!,
          _bangumiEpisodeIdMeta,
        ),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('subject_title')) {
      context.handle(
        _subjectTitleMeta,
        subjectTitle.isAcceptableOrUnknown(
          data['subject_title']!,
          _subjectTitleMeta,
        ),
      );
    }
    if (data.containsKey('episode_label')) {
      context.handle(
        _episodeLabelMeta,
        episodeLabel.isAcceptableOrUnknown(
          data['episode_label']!,
          _episodeLabelMeta,
        ),
      );
    }
    if (data.containsKey('local_file_path')) {
      context.handle(
        _localFilePathMeta,
        localFilePath.isAcceptableOrUnknown(
          data['local_file_path']!,
          _localFilePathMeta,
        ),
      );
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    }
    if (data.containsKey('position_ms')) {
      context.handle(
        _positionMsMeta,
        positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mediaKey};
  @override
  PlaybackProgressRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaybackProgressRecord(
      mediaKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_key'],
      )!,
      bangumiSubjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bangumi_subject_id'],
      )!,
      bangumiEpisodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bangumi_episode_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      subjectTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_title'],
      )!,
      episodeLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}episode_label'],
      )!,
      localFilePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_file_path'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      positionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_ms'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  $PlaybackProgressRecordsTable createAlias(String alias) {
    return $PlaybackProgressRecordsTable(attachedDatabase, alias);
  }
}

class PlaybackProgressRecord extends DataClass
    implements Insertable<PlaybackProgressRecord> {
  final String mediaKey;
  final int bangumiSubjectId;
  final int bangumiEpisodeId;
  final String title;
  final String subjectTitle;
  final String episodeLabel;
  final String localFilePath;
  final String url;
  final int positionMs;
  final int durationMs;
  final int updatedAtMs;
  const PlaybackProgressRecord({
    required this.mediaKey,
    required this.bangumiSubjectId,
    required this.bangumiEpisodeId,
    required this.title,
    required this.subjectTitle,
    required this.episodeLabel,
    required this.localFilePath,
    required this.url,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['media_key'] = Variable<String>(mediaKey);
    map['bangumi_subject_id'] = Variable<int>(bangumiSubjectId);
    map['bangumi_episode_id'] = Variable<int>(bangumiEpisodeId);
    map['title'] = Variable<String>(title);
    map['subject_title'] = Variable<String>(subjectTitle);
    map['episode_label'] = Variable<String>(episodeLabel);
    map['local_file_path'] = Variable<String>(localFilePath);
    map['url'] = Variable<String>(url);
    map['position_ms'] = Variable<int>(positionMs);
    map['duration_ms'] = Variable<int>(durationMs);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  PlaybackProgressRecordsCompanion toCompanion(bool nullToAbsent) {
    return PlaybackProgressRecordsCompanion(
      mediaKey: Value(mediaKey),
      bangumiSubjectId: Value(bangumiSubjectId),
      bangumiEpisodeId: Value(bangumiEpisodeId),
      title: Value(title),
      subjectTitle: Value(subjectTitle),
      episodeLabel: Value(episodeLabel),
      localFilePath: Value(localFilePath),
      url: Value(url),
      positionMs: Value(positionMs),
      durationMs: Value(durationMs),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory PlaybackProgressRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaybackProgressRecord(
      mediaKey: serializer.fromJson<String>(json['mediaKey']),
      bangumiSubjectId: serializer.fromJson<int>(json['bangumiSubjectId']),
      bangumiEpisodeId: serializer.fromJson<int>(json['bangumiEpisodeId']),
      title: serializer.fromJson<String>(json['title']),
      subjectTitle: serializer.fromJson<String>(json['subjectTitle']),
      episodeLabel: serializer.fromJson<String>(json['episodeLabel']),
      localFilePath: serializer.fromJson<String>(json['localFilePath']),
      url: serializer.fromJson<String>(json['url']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mediaKey': serializer.toJson<String>(mediaKey),
      'bangumiSubjectId': serializer.toJson<int>(bangumiSubjectId),
      'bangumiEpisodeId': serializer.toJson<int>(bangumiEpisodeId),
      'title': serializer.toJson<String>(title),
      'subjectTitle': serializer.toJson<String>(subjectTitle),
      'episodeLabel': serializer.toJson<String>(episodeLabel),
      'localFilePath': serializer.toJson<String>(localFilePath),
      'url': serializer.toJson<String>(url),
      'positionMs': serializer.toJson<int>(positionMs),
      'durationMs': serializer.toJson<int>(durationMs),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
    };
  }

  PlaybackProgressRecord copyWith({
    String? mediaKey,
    int? bangumiSubjectId,
    int? bangumiEpisodeId,
    String? title,
    String? subjectTitle,
    String? episodeLabel,
    String? localFilePath,
    String? url,
    int? positionMs,
    int? durationMs,
    int? updatedAtMs,
  }) => PlaybackProgressRecord(
    mediaKey: mediaKey ?? this.mediaKey,
    bangumiSubjectId: bangumiSubjectId ?? this.bangumiSubjectId,
    bangumiEpisodeId: bangumiEpisodeId ?? this.bangumiEpisodeId,
    title: title ?? this.title,
    subjectTitle: subjectTitle ?? this.subjectTitle,
    episodeLabel: episodeLabel ?? this.episodeLabel,
    localFilePath: localFilePath ?? this.localFilePath,
    url: url ?? this.url,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs ?? this.durationMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  PlaybackProgressRecord copyWithCompanion(
    PlaybackProgressRecordsCompanion data,
  ) {
    return PlaybackProgressRecord(
      mediaKey: data.mediaKey.present ? data.mediaKey.value : this.mediaKey,
      bangumiSubjectId: data.bangumiSubjectId.present
          ? data.bangumiSubjectId.value
          : this.bangumiSubjectId,
      bangumiEpisodeId: data.bangumiEpisodeId.present
          ? data.bangumiEpisodeId.value
          : this.bangumiEpisodeId,
      title: data.title.present ? data.title.value : this.title,
      subjectTitle: data.subjectTitle.present
          ? data.subjectTitle.value
          : this.subjectTitle,
      episodeLabel: data.episodeLabel.present
          ? data.episodeLabel.value
          : this.episodeLabel,
      localFilePath: data.localFilePath.present
          ? data.localFilePath.value
          : this.localFilePath,
      url: data.url.present ? data.url.value : this.url,
      positionMs: data.positionMs.present
          ? data.positionMs.value
          : this.positionMs,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackProgressRecord(')
          ..write('mediaKey: $mediaKey, ')
          ..write('bangumiSubjectId: $bangumiSubjectId, ')
          ..write('bangumiEpisodeId: $bangumiEpisodeId, ')
          ..write('title: $title, ')
          ..write('subjectTitle: $subjectTitle, ')
          ..write('episodeLabel: $episodeLabel, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('url: $url, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    mediaKey,
    bangumiSubjectId,
    bangumiEpisodeId,
    title,
    subjectTitle,
    episodeLabel,
    localFilePath,
    url,
    positionMs,
    durationMs,
    updatedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaybackProgressRecord &&
          other.mediaKey == this.mediaKey &&
          other.bangumiSubjectId == this.bangumiSubjectId &&
          other.bangumiEpisodeId == this.bangumiEpisodeId &&
          other.title == this.title &&
          other.subjectTitle == this.subjectTitle &&
          other.episodeLabel == this.episodeLabel &&
          other.localFilePath == this.localFilePath &&
          other.url == this.url &&
          other.positionMs == this.positionMs &&
          other.durationMs == this.durationMs &&
          other.updatedAtMs == this.updatedAtMs);
}

class PlaybackProgressRecordsCompanion
    extends UpdateCompanion<PlaybackProgressRecord> {
  final Value<String> mediaKey;
  final Value<int> bangumiSubjectId;
  final Value<int> bangumiEpisodeId;
  final Value<String> title;
  final Value<String> subjectTitle;
  final Value<String> episodeLabel;
  final Value<String> localFilePath;
  final Value<String> url;
  final Value<int> positionMs;
  final Value<int> durationMs;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const PlaybackProgressRecordsCompanion({
    this.mediaKey = const Value.absent(),
    this.bangumiSubjectId = const Value.absent(),
    this.bangumiEpisodeId = const Value.absent(),
    this.title = const Value.absent(),
    this.subjectTitle = const Value.absent(),
    this.episodeLabel = const Value.absent(),
    this.localFilePath = const Value.absent(),
    this.url = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaybackProgressRecordsCompanion.insert({
    required String mediaKey,
    this.bangumiSubjectId = const Value.absent(),
    this.bangumiEpisodeId = const Value.absent(),
    this.title = const Value.absent(),
    this.subjectTitle = const Value.absent(),
    this.episodeLabel = const Value.absent(),
    this.localFilePath = const Value.absent(),
    this.url = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : mediaKey = Value(mediaKey);
  static Insertable<PlaybackProgressRecord> custom({
    Expression<String>? mediaKey,
    Expression<int>? bangumiSubjectId,
    Expression<int>? bangumiEpisodeId,
    Expression<String>? title,
    Expression<String>? subjectTitle,
    Expression<String>? episodeLabel,
    Expression<String>? localFilePath,
    Expression<String>? url,
    Expression<int>? positionMs,
    Expression<int>? durationMs,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mediaKey != null) 'media_key': mediaKey,
      if (bangumiSubjectId != null) 'bangumi_subject_id': bangumiSubjectId,
      if (bangumiEpisodeId != null) 'bangumi_episode_id': bangumiEpisodeId,
      if (title != null) 'title': title,
      if (subjectTitle != null) 'subject_title': subjectTitle,
      if (episodeLabel != null) 'episode_label': episodeLabel,
      if (localFilePath != null) 'local_file_path': localFilePath,
      if (url != null) 'url': url,
      if (positionMs != null) 'position_ms': positionMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaybackProgressRecordsCompanion copyWith({
    Value<String>? mediaKey,
    Value<int>? bangumiSubjectId,
    Value<int>? bangumiEpisodeId,
    Value<String>? title,
    Value<String>? subjectTitle,
    Value<String>? episodeLabel,
    Value<String>? localFilePath,
    Value<String>? url,
    Value<int>? positionMs,
    Value<int>? durationMs,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return PlaybackProgressRecordsCompanion(
      mediaKey: mediaKey ?? this.mediaKey,
      bangumiSubjectId: bangumiSubjectId ?? this.bangumiSubjectId,
      bangumiEpisodeId: bangumiEpisodeId ?? this.bangumiEpisodeId,
      title: title ?? this.title,
      subjectTitle: subjectTitle ?? this.subjectTitle,
      episodeLabel: episodeLabel ?? this.episodeLabel,
      localFilePath: localFilePath ?? this.localFilePath,
      url: url ?? this.url,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mediaKey.present) {
      map['media_key'] = Variable<String>(mediaKey.value);
    }
    if (bangumiSubjectId.present) {
      map['bangumi_subject_id'] = Variable<int>(bangumiSubjectId.value);
    }
    if (bangumiEpisodeId.present) {
      map['bangumi_episode_id'] = Variable<int>(bangumiEpisodeId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (subjectTitle.present) {
      map['subject_title'] = Variable<String>(subjectTitle.value);
    }
    if (episodeLabel.present) {
      map['episode_label'] = Variable<String>(episodeLabel.value);
    }
    if (localFilePath.present) {
      map['local_file_path'] = Variable<String>(localFilePath.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackProgressRecordsCompanion(')
          ..write('mediaKey: $mediaKey, ')
          ..write('bangumiSubjectId: $bangumiSubjectId, ')
          ..write('bangumiEpisodeId: $bangumiEpisodeId, ')
          ..write('title: $title, ')
          ..write('subjectTitle: $subjectTitle, ')
          ..write('episodeLabel: $episodeLabel, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('url: $url, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AnimeSubjectsTable animeSubjects = $AnimeSubjectsTable(this);
  late final $AnimeEpisodesTable animeEpisodes = $AnimeEpisodesTable(this);
  late final $DownloadTaskRecordsTable downloadTaskRecords =
      $DownloadTaskRecordsTable(this);
  late final $PlaybackProgressRecordsTable playbackProgressRecords =
      $PlaybackProgressRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    animeSubjects,
    animeEpisodes,
    downloadTaskRecords,
    playbackProgressRecords,
  ];
}

typedef $$AnimeSubjectsTableCreateCompanionBuilder =
    AnimeSubjectsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> nameCn,
      Value<String> imageUrl,
      Value<String> score,
      Value<int> episodeCount,
      Value<int> updatedAtMs,
    });
typedef $$AnimeSubjectsTableUpdateCompanionBuilder =
    AnimeSubjectsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> nameCn,
      Value<String> imageUrl,
      Value<String> score,
      Value<int> episodeCount,
      Value<int> updatedAtMs,
    });

class $$AnimeSubjectsTableFilterComposer
    extends Composer<_$AppDatabase, $AnimeSubjectsTable> {
  $$AnimeSubjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameCn => $composableBuilder(
    column: $table.nameCn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episodeCount => $composableBuilder(
    column: $table.episodeCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AnimeSubjectsTableOrderingComposer
    extends Composer<_$AppDatabase, $AnimeSubjectsTable> {
  $$AnimeSubjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameCn => $composableBuilder(
    column: $table.nameCn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episodeCount => $composableBuilder(
    column: $table.episodeCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AnimeSubjectsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AnimeSubjectsTable> {
  $$AnimeSubjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nameCn =>
      $composableBuilder(column: $table.nameCn, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<String> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<int> get episodeCount => $composableBuilder(
    column: $table.episodeCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$AnimeSubjectsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AnimeSubjectsTable,
          AnimeSubject,
          $$AnimeSubjectsTableFilterComposer,
          $$AnimeSubjectsTableOrderingComposer,
          $$AnimeSubjectsTableAnnotationComposer,
          $$AnimeSubjectsTableCreateCompanionBuilder,
          $$AnimeSubjectsTableUpdateCompanionBuilder,
          (
            AnimeSubject,
            BaseReferences<_$AppDatabase, $AnimeSubjectsTable, AnimeSubject>,
          ),
          AnimeSubject,
          PrefetchHooks Function()
        > {
  $$AnimeSubjectsTableTableManager(_$AppDatabase db, $AnimeSubjectsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AnimeSubjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AnimeSubjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AnimeSubjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> nameCn = const Value.absent(),
                Value<String> imageUrl = const Value.absent(),
                Value<String> score = const Value.absent(),
                Value<int> episodeCount = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
              }) => AnimeSubjectsCompanion(
                id: id,
                name: name,
                nameCn: nameCn,
                imageUrl: imageUrl,
                score: score,
                episodeCount: episodeCount,
                updatedAtMs: updatedAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> nameCn = const Value.absent(),
                Value<String> imageUrl = const Value.absent(),
                Value<String> score = const Value.absent(),
                Value<int> episodeCount = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
              }) => AnimeSubjectsCompanion.insert(
                id: id,
                name: name,
                nameCn: nameCn,
                imageUrl: imageUrl,
                score: score,
                episodeCount: episodeCount,
                updatedAtMs: updatedAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AnimeSubjectsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AnimeSubjectsTable,
      AnimeSubject,
      $$AnimeSubjectsTableFilterComposer,
      $$AnimeSubjectsTableOrderingComposer,
      $$AnimeSubjectsTableAnnotationComposer,
      $$AnimeSubjectsTableCreateCompanionBuilder,
      $$AnimeSubjectsTableUpdateCompanionBuilder,
      (
        AnimeSubject,
        BaseReferences<_$AppDatabase, $AnimeSubjectsTable, AnimeSubject>,
      ),
      AnimeSubject,
      PrefetchHooks Function()
    >;
typedef $$AnimeEpisodesTableCreateCompanionBuilder =
    AnimeEpisodesCompanion Function({
      Value<int> id,
      required int subjectId,
      Value<int> episodeNumber,
      Value<String> title,
      Value<String> titleCn,
      Value<int> watchedPositionMs,
      Value<int> durationMs,
      Value<bool> isWatched,
      Value<int> updatedAtMs,
    });
typedef $$AnimeEpisodesTableUpdateCompanionBuilder =
    AnimeEpisodesCompanion Function({
      Value<int> id,
      Value<int> subjectId,
      Value<int> episodeNumber,
      Value<String> title,
      Value<String> titleCn,
      Value<int> watchedPositionMs,
      Value<int> durationMs,
      Value<bool> isWatched,
      Value<int> updatedAtMs,
    });

class $$AnimeEpisodesTableFilterComposer
    extends Composer<_$AppDatabase, $AnimeEpisodesTable> {
  $$AnimeEpisodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleCn => $composableBuilder(
    column: $table.titleCn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get watchedPositionMs => $composableBuilder(
    column: $table.watchedPositionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isWatched => $composableBuilder(
    column: $table.isWatched,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AnimeEpisodesTableOrderingComposer
    extends Composer<_$AppDatabase, $AnimeEpisodesTable> {
  $$AnimeEpisodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleCn => $composableBuilder(
    column: $table.titleCn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get watchedPositionMs => $composableBuilder(
    column: $table.watchedPositionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isWatched => $composableBuilder(
    column: $table.isWatched,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AnimeEpisodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AnimeEpisodesTable> {
  $$AnimeEpisodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get subjectId =>
      $composableBuilder(column: $table.subjectId, builder: (column) => column);

  GeneratedColumn<int> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get titleCn =>
      $composableBuilder(column: $table.titleCn, builder: (column) => column);

  GeneratedColumn<int> get watchedPositionMs => $composableBuilder(
    column: $table.watchedPositionMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isWatched =>
      $composableBuilder(column: $table.isWatched, builder: (column) => column);

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$AnimeEpisodesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AnimeEpisodesTable,
          AnimeEpisode,
          $$AnimeEpisodesTableFilterComposer,
          $$AnimeEpisodesTableOrderingComposer,
          $$AnimeEpisodesTableAnnotationComposer,
          $$AnimeEpisodesTableCreateCompanionBuilder,
          $$AnimeEpisodesTableUpdateCompanionBuilder,
          (
            AnimeEpisode,
            BaseReferences<_$AppDatabase, $AnimeEpisodesTable, AnimeEpisode>,
          ),
          AnimeEpisode,
          PrefetchHooks Function()
        > {
  $$AnimeEpisodesTableTableManager(_$AppDatabase db, $AnimeEpisodesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AnimeEpisodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AnimeEpisodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AnimeEpisodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> subjectId = const Value.absent(),
                Value<int> episodeNumber = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> titleCn = const Value.absent(),
                Value<int> watchedPositionMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<bool> isWatched = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
              }) => AnimeEpisodesCompanion(
                id: id,
                subjectId: subjectId,
                episodeNumber: episodeNumber,
                title: title,
                titleCn: titleCn,
                watchedPositionMs: watchedPositionMs,
                durationMs: durationMs,
                isWatched: isWatched,
                updatedAtMs: updatedAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int subjectId,
                Value<int> episodeNumber = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> titleCn = const Value.absent(),
                Value<int> watchedPositionMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<bool> isWatched = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
              }) => AnimeEpisodesCompanion.insert(
                id: id,
                subjectId: subjectId,
                episodeNumber: episodeNumber,
                title: title,
                titleCn: titleCn,
                watchedPositionMs: watchedPositionMs,
                durationMs: durationMs,
                isWatched: isWatched,
                updatedAtMs: updatedAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AnimeEpisodesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AnimeEpisodesTable,
      AnimeEpisode,
      $$AnimeEpisodesTableFilterComposer,
      $$AnimeEpisodesTableOrderingComposer,
      $$AnimeEpisodesTableAnnotationComposer,
      $$AnimeEpisodesTableCreateCompanionBuilder,
      $$AnimeEpisodesTableUpdateCompanionBuilder,
      (
        AnimeEpisode,
        BaseReferences<_$AppDatabase, $AnimeEpisodesTable, AnimeEpisode>,
      ),
      AnimeEpisode,
      PrefetchHooks Function()
    >;
typedef $$DownloadTaskRecordsTableCreateCompanionBuilder =
    DownloadTaskRecordsCompanion Function({
      required String hash,
      Value<String> title,
      Value<String> url,
      Value<String> savePath,
      Value<String> targetPath,
      Value<int> targetSize,
      Value<String> subjectTitle,
      Value<String> episodeLabel,
      Value<int> bangumiSubjectId,
      Value<int> bangumiEpisodeId,
      Value<bool> isCompleted,
      Value<bool> isPaused,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });
typedef $$DownloadTaskRecordsTableUpdateCompanionBuilder =
    DownloadTaskRecordsCompanion Function({
      Value<String> hash,
      Value<String> title,
      Value<String> url,
      Value<String> savePath,
      Value<String> targetPath,
      Value<int> targetSize,
      Value<String> subjectTitle,
      Value<String> episodeLabel,
      Value<int> bangumiSubjectId,
      Value<int> bangumiEpisodeId,
      Value<bool> isCompleted,
      Value<bool> isPaused,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$DownloadTaskRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $DownloadTaskRecordsTable> {
  $$DownloadTaskRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get hash => $composableBuilder(
    column: $table.hash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get savePath => $composableBuilder(
    column: $table.savePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetPath => $composableBuilder(
    column: $table.targetPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetSize => $composableBuilder(
    column: $table.targetSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subjectTitle => $composableBuilder(
    column: $table.subjectTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get episodeLabel => $composableBuilder(
    column: $table.episodeLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bangumiSubjectId => $composableBuilder(
    column: $table.bangumiSubjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bangumiEpisodeId => $composableBuilder(
    column: $table.bangumiEpisodeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPaused => $composableBuilder(
    column: $table.isPaused,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DownloadTaskRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $DownloadTaskRecordsTable> {
  $$DownloadTaskRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get hash => $composableBuilder(
    column: $table.hash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get savePath => $composableBuilder(
    column: $table.savePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetPath => $composableBuilder(
    column: $table.targetPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetSize => $composableBuilder(
    column: $table.targetSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subjectTitle => $composableBuilder(
    column: $table.subjectTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get episodeLabel => $composableBuilder(
    column: $table.episodeLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bangumiSubjectId => $composableBuilder(
    column: $table.bangumiSubjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bangumiEpisodeId => $composableBuilder(
    column: $table.bangumiEpisodeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPaused => $composableBuilder(
    column: $table.isPaused,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DownloadTaskRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DownloadTaskRecordsTable> {
  $$DownloadTaskRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get hash =>
      $composableBuilder(column: $table.hash, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get savePath =>
      $composableBuilder(column: $table.savePath, builder: (column) => column);

  GeneratedColumn<String> get targetPath => $composableBuilder(
    column: $table.targetPath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get targetSize => $composableBuilder(
    column: $table.targetSize,
    builder: (column) => column,
  );

  GeneratedColumn<String> get subjectTitle => $composableBuilder(
    column: $table.subjectTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get episodeLabel => $composableBuilder(
    column: $table.episodeLabel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bangumiSubjectId => $composableBuilder(
    column: $table.bangumiSubjectId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bangumiEpisodeId => $composableBuilder(
    column: $table.bangumiEpisodeId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPaused =>
      $composableBuilder(column: $table.isPaused, builder: (column) => column);

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$DownloadTaskRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DownloadTaskRecordsTable,
          DownloadTaskRecord,
          $$DownloadTaskRecordsTableFilterComposer,
          $$DownloadTaskRecordsTableOrderingComposer,
          $$DownloadTaskRecordsTableAnnotationComposer,
          $$DownloadTaskRecordsTableCreateCompanionBuilder,
          $$DownloadTaskRecordsTableUpdateCompanionBuilder,
          (
            DownloadTaskRecord,
            BaseReferences<
              _$AppDatabase,
              $DownloadTaskRecordsTable,
              DownloadTaskRecord
            >,
          ),
          DownloadTaskRecord,
          PrefetchHooks Function()
        > {
  $$DownloadTaskRecordsTableTableManager(
    _$AppDatabase db,
    $DownloadTaskRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadTaskRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadTaskRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DownloadTaskRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> hash = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String> savePath = const Value.absent(),
                Value<String> targetPath = const Value.absent(),
                Value<int> targetSize = const Value.absent(),
                Value<String> subjectTitle = const Value.absent(),
                Value<String> episodeLabel = const Value.absent(),
                Value<int> bangumiSubjectId = const Value.absent(),
                Value<int> bangumiEpisodeId = const Value.absent(),
                Value<bool> isCompleted = const Value.absent(),
                Value<bool> isPaused = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadTaskRecordsCompanion(
                hash: hash,
                title: title,
                url: url,
                savePath: savePath,
                targetPath: targetPath,
                targetSize: targetSize,
                subjectTitle: subjectTitle,
                episodeLabel: episodeLabel,
                bangumiSubjectId: bangumiSubjectId,
                bangumiEpisodeId: bangumiEpisodeId,
                isCompleted: isCompleted,
                isPaused: isPaused,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String hash,
                Value<String> title = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String> savePath = const Value.absent(),
                Value<String> targetPath = const Value.absent(),
                Value<int> targetSize = const Value.absent(),
                Value<String> subjectTitle = const Value.absent(),
                Value<String> episodeLabel = const Value.absent(),
                Value<int> bangumiSubjectId = const Value.absent(),
                Value<int> bangumiEpisodeId = const Value.absent(),
                Value<bool> isCompleted = const Value.absent(),
                Value<bool> isPaused = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadTaskRecordsCompanion.insert(
                hash: hash,
                title: title,
                url: url,
                savePath: savePath,
                targetPath: targetPath,
                targetSize: targetSize,
                subjectTitle: subjectTitle,
                episodeLabel: episodeLabel,
                bangumiSubjectId: bangumiSubjectId,
                bangumiEpisodeId: bangumiEpisodeId,
                isCompleted: isCompleted,
                isPaused: isPaused,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DownloadTaskRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DownloadTaskRecordsTable,
      DownloadTaskRecord,
      $$DownloadTaskRecordsTableFilterComposer,
      $$DownloadTaskRecordsTableOrderingComposer,
      $$DownloadTaskRecordsTableAnnotationComposer,
      $$DownloadTaskRecordsTableCreateCompanionBuilder,
      $$DownloadTaskRecordsTableUpdateCompanionBuilder,
      (
        DownloadTaskRecord,
        BaseReferences<
          _$AppDatabase,
          $DownloadTaskRecordsTable,
          DownloadTaskRecord
        >,
      ),
      DownloadTaskRecord,
      PrefetchHooks Function()
    >;
typedef $$PlaybackProgressRecordsTableCreateCompanionBuilder =
    PlaybackProgressRecordsCompanion Function({
      required String mediaKey,
      Value<int> bangumiSubjectId,
      Value<int> bangumiEpisodeId,
      Value<String> title,
      Value<String> subjectTitle,
      Value<String> episodeLabel,
      Value<String> localFilePath,
      Value<String> url,
      Value<int> positionMs,
      Value<int> durationMs,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });
typedef $$PlaybackProgressRecordsTableUpdateCompanionBuilder =
    PlaybackProgressRecordsCompanion Function({
      Value<String> mediaKey,
      Value<int> bangumiSubjectId,
      Value<int> bangumiEpisodeId,
      Value<String> title,
      Value<String> subjectTitle,
      Value<String> episodeLabel,
      Value<String> localFilePath,
      Value<String> url,
      Value<int> positionMs,
      Value<int> durationMs,
      Value<int> updatedAtMs,
      Value<int> rowid,
    });

class $$PlaybackProgressRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaybackProgressRecordsTable> {
  $$PlaybackProgressRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mediaKey => $composableBuilder(
    column: $table.mediaKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bangumiSubjectId => $composableBuilder(
    column: $table.bangumiSubjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bangumiEpisodeId => $composableBuilder(
    column: $table.bangumiEpisodeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subjectTitle => $composableBuilder(
    column: $table.subjectTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get episodeLabel => $composableBuilder(
    column: $table.episodeLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaybackProgressRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaybackProgressRecordsTable> {
  $$PlaybackProgressRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mediaKey => $composableBuilder(
    column: $table.mediaKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bangumiSubjectId => $composableBuilder(
    column: $table.bangumiSubjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bangumiEpisodeId => $composableBuilder(
    column: $table.bangumiEpisodeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subjectTitle => $composableBuilder(
    column: $table.subjectTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get episodeLabel => $composableBuilder(
    column: $table.episodeLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaybackProgressRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaybackProgressRecordsTable> {
  $$PlaybackProgressRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mediaKey =>
      $composableBuilder(column: $table.mediaKey, builder: (column) => column);

  GeneratedColumn<int> get bangumiSubjectId => $composableBuilder(
    column: $table.bangumiSubjectId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bangumiEpisodeId => $composableBuilder(
    column: $table.bangumiEpisodeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get subjectTitle => $composableBuilder(
    column: $table.subjectTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get episodeLabel => $composableBuilder(
    column: $table.episodeLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );
}

class $$PlaybackProgressRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaybackProgressRecordsTable,
          PlaybackProgressRecord,
          $$PlaybackProgressRecordsTableFilterComposer,
          $$PlaybackProgressRecordsTableOrderingComposer,
          $$PlaybackProgressRecordsTableAnnotationComposer,
          $$PlaybackProgressRecordsTableCreateCompanionBuilder,
          $$PlaybackProgressRecordsTableUpdateCompanionBuilder,
          (
            PlaybackProgressRecord,
            BaseReferences<
              _$AppDatabase,
              $PlaybackProgressRecordsTable,
              PlaybackProgressRecord
            >,
          ),
          PlaybackProgressRecord,
          PrefetchHooks Function()
        > {
  $$PlaybackProgressRecordsTableTableManager(
    _$AppDatabase db,
    $PlaybackProgressRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaybackProgressRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$PlaybackProgressRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PlaybackProgressRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> mediaKey = const Value.absent(),
                Value<int> bangumiSubjectId = const Value.absent(),
                Value<int> bangumiEpisodeId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> subjectTitle = const Value.absent(),
                Value<String> episodeLabel = const Value.absent(),
                Value<String> localFilePath = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaybackProgressRecordsCompanion(
                mediaKey: mediaKey,
                bangumiSubjectId: bangumiSubjectId,
                bangumiEpisodeId: bangumiEpisodeId,
                title: title,
                subjectTitle: subjectTitle,
                episodeLabel: episodeLabel,
                localFilePath: localFilePath,
                url: url,
                positionMs: positionMs,
                durationMs: durationMs,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mediaKey,
                Value<int> bangumiSubjectId = const Value.absent(),
                Value<int> bangumiEpisodeId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> subjectTitle = const Value.absent(),
                Value<String> episodeLabel = const Value.absent(),
                Value<String> localFilePath = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaybackProgressRecordsCompanion.insert(
                mediaKey: mediaKey,
                bangumiSubjectId: bangumiSubjectId,
                bangumiEpisodeId: bangumiEpisodeId,
                title: title,
                subjectTitle: subjectTitle,
                episodeLabel: episodeLabel,
                localFilePath: localFilePath,
                url: url,
                positionMs: positionMs,
                durationMs: durationMs,
                updatedAtMs: updatedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaybackProgressRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaybackProgressRecordsTable,
      PlaybackProgressRecord,
      $$PlaybackProgressRecordsTableFilterComposer,
      $$PlaybackProgressRecordsTableOrderingComposer,
      $$PlaybackProgressRecordsTableAnnotationComposer,
      $$PlaybackProgressRecordsTableCreateCompanionBuilder,
      $$PlaybackProgressRecordsTableUpdateCompanionBuilder,
      (
        PlaybackProgressRecord,
        BaseReferences<
          _$AppDatabase,
          $PlaybackProgressRecordsTable,
          PlaybackProgressRecord
        >,
      ),
      PlaybackProgressRecord,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AnimeSubjectsTableTableManager get animeSubjects =>
      $$AnimeSubjectsTableTableManager(_db, _db.animeSubjects);
  $$AnimeEpisodesTableTableManager get animeEpisodes =>
      $$AnimeEpisodesTableTableManager(_db, _db.animeEpisodes);
  $$DownloadTaskRecordsTableTableManager get downloadTaskRecords =>
      $$DownloadTaskRecordsTableTableManager(_db, _db.downloadTaskRecords);
  $$PlaybackProgressRecordsTableTableManager get playbackProgressRecords =>
      $$PlaybackProgressRecordsTableTableManager(
        _db,
        _db.playbackProgressRecords,
      );
}

import '../utils/episode_helpers.dart';

/// A strongly‑typed Bangumi episode, replacing ad‑hoc [Map<String, dynamic>]
/// used across detail_page, episode_watch_page, torrent_media_resolver, and
/// BangumiApi.
class Episode {
  final int id;
  final int subjectId;
  final int episodeNumber;
  final int sort;
  final String title;
  final String titleCn;
  final String airdate;
  final String description;
  final String duration;

  const Episode({
    required this.id,
    this.subjectId = 0,
    this.episodeNumber = 0,
    this.sort = 0,
    this.title = '',
    this.titleCn = '',
    this.airdate = '',
    this.description = '',
    this.duration = '',
  });

  factory Episode.fromJson(Map<String, dynamic> json, {int subjectId = 0}) {
    return Episode(
      id: safeInt(json['id']),
      subjectId: subjectId,
      episodeNumber: safeInt(json['ep'] ?? json['sort']),
      sort: safeInt(json['sort']),
      title: (json['name']?.toString() ?? '').trim(),
      titleCn: (json['name_cn']?.toString() ?? '').trim(),
      airdate: (json['airdate']?.toString() ?? '').trim(),
      description: (json['desc']?.toString() ?? '').trim(),
      duration: (json['duration']?.toString() ?? '').trim(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'subject_id': subjectId,
    'ep': episodeNumber,
    'sort': sort,
    'name': title,
    'name_cn': titleCn,
    'airdate': airdate,
    'desc': description,
    'duration': duration,
  };

  /// Convenience — delegates to [episodeTitle] from episode_helpers.
  String get displayTitle => episodeTitle(toJson());

  /// Convenience — delegates to [episodePlainTitle] from episode_helpers.
  String get plainTitle => episodePlainTitle(toJson());

  /// Convenience — delegates to [episodeDescription] from episode_helpers.
  String get desc => episodeDescription(toJson());

  String get displayNumber => episodeNumber > 0 ? '$episodeNumber' : '?';

  /// Builds a query key for online‑source lookup.
  String get chartKey => episodeNumber > 0 ? '$episodeNumber' : id.toString();
}

class DandanplayMatchResult {
  final int episodeId;
  final int animeId;
  final String animeTitle;
  final String episodeTitle;
  final double shift;

  const DandanplayMatchResult({
    required this.episodeId,
    required this.animeId,
    required this.animeTitle,
    required this.episodeTitle,
    this.shift = 0,
  });

  factory DandanplayMatchResult.fromJson(Map<String, dynamic> json) {
    return DandanplayMatchResult(
      episodeId: int.tryParse(json['episodeId']?.toString() ?? '') ?? 0,
      animeId: int.tryParse(json['animeId']?.toString() ?? '') ?? 0,
      animeTitle: json['animeTitle']?.toString() ?? '',
      episodeTitle: json['episodeTitle']?.toString() ?? '',
      shift: _finiteSeconds(json['shift']),
    );
  }

  String get displayTitle =>
      '${animeTitle.trim()}${episodeTitle.trim().isNotEmpty ? ' · ${episodeTitle.trim()}' : ''}';

  Map<String, dynamic> toJson() => {
    'episodeId': episodeId,
    'animeId': animeId,
    'animeTitle': animeTitle,
    'episodeTitle': episodeTitle,
    'shift': shift,
  };
}

class DandanplayComment {
  final int id;
  final Duration appearAt;
  final int mode;
  final int color;
  final String userId;
  final String text;

  const DandanplayComment({
    required this.id,
    required this.appearAt,
    required this.mode,
    required this.color,
    required this.userId,
    required this.text,
  });

  factory DandanplayComment.fromJson(Map<String, dynamic> json) {
    final String rawP = json['p']?.toString() ?? '';
    final List<String> parts = rawP.split(',');
    final double seconds = parts.isNotEmpty
        ? double.tryParse(parts[0].trim()) ?? 0
        : 0;
    final int mode = parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 1 : 1;
    final int color = parts.length > 2
        ? int.tryParse(parts[2].trim()) ?? 0xFFFFFF
        : 0xFFFFFF;
    final String userId = parts.length > 3 ? parts[3].trim() : '';

    return DandanplayComment(
      id: int.tryParse(json['cid']?.toString() ?? '') ?? 0,
      appearAt: Duration(
        milliseconds:
            (seconds.isFinite ? seconds.clamp(0, 86401) * 1000 : 86401000)
                .round(),
      ),
      mode: mode,
      color: color.clamp(0, 0xffffff),
      userId: userId,
      text: json['m']?.toString() ?? '',
    );
  }

  DandanplayComment shiftBy(Duration offset) {
    final Duration shifted = appearAt + offset;
    return DandanplayComment(
      id: id,
      appearAt: shifted.isNegative ? Duration.zero : shifted,
      mode: mode,
      color: color,
      userId: userId,
      text: text,
    );
  }
}

class DandanplayLoadResult {
  final DandanplayMatchResult match;
  final List<DandanplayComment> comments;
  final String source;
  final bool isStale;

  const DandanplayLoadResult({
    required this.match,
    required this.comments,
    this.source = 'dandanplay',
    this.isStale = false,
  });
}

double _finiteSeconds(Object? value) {
  final number = double.tryParse(value?.toString() ?? '') ?? 0;
  return number.isFinite ? number.clamp(-86400, 86400).toDouble() : 0;
}

class DandanplayException implements Exception {
  const DandanplayException(this.message, {this.code = '', this.status});
  final String message;
  final String code;
  final int? status;
  @override
  String toString() => message;
}

class DandanplayMatchRequired extends DandanplayException {
  const DandanplayMatchRequired(this.candidates)
    : super('找到多个可能的剧集，请手动匹配弹幕。', code: 'ambiguous_match');
  final List<DandanplayMatchResult> candidates;
}

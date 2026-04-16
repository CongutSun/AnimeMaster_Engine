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
      shift: double.tryParse(json['shift']?.toString() ?? '') ?? 0,
    );
  }

  String get displayTitle =>
      '${animeTitle.trim()}${episodeTitle.trim().isNotEmpty ? ' · ${episodeTitle.trim()}' : ''}';
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
      appearAt: Duration(milliseconds: (seconds * 1000).round()),
      mode: mode,
      color: color,
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

  const DandanplayLoadResult({required this.match, required this.comments});
}

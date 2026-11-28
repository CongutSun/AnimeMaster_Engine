import '../utils/episode_helpers.dart' as episodes;
import '../utils/bilibili_episode_matcher.dart';
import '../utils/task_title_parser.dart';

class CacheEpisodeFile {
  const CacheEpisodeFile(
    this.path,
    this.size,
    this.label, {
    this.number = 0,
    this.episodeId = 0,
    this.manual = false,
  });
  final String path;
  final int size;
  final String label;
  final int number;
  final int episodeId;
  final bool manual;

  static bool isVideo(String name) => RegExp(
    r'\.(rmvb|mkv|mp4|avi|mov|m4v|ts|m2ts|webm|flv|wmv|mpg|mpeg|ogm)$',
    caseSensitive: false,
  ).hasMatch(name);
  static CacheEpisodeFile identify(
    String path,
    int size,
    String name, {
    String subject = '',
    String parent = '',
    List<Map<String, dynamic>> catalog = const [],
  }) {
    final stem = isVideo(name)
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    final special =
        RegExp(
          r'预告|特典|片头|片尾|花絮|解说|混剪|特别篇|番外|(?<![a-z])(?:NCOP|NCED|OP|ED|SP|PV|OVA|OAD|Trailer|Sample)(?:\d+)?(?![a-z])',
          caseSensitive: false,
        ).hasMatch(stem) ||
        RegExp(
          r'(?:^|[/\\])(?:extras?|specials?|sp|bonus|特典|花絮|预告)(?:[/\\]|$)',
          caseSensitive: false,
        ).hasMatch(parent);
    final range = RegExp(
      r'\d{1,3}\s*(?:集|話|话)?\s*[-~～至+&]\s*(?:第|S\d+E|E(?:P)?)?\s*\d{1,3}(?!\d)|S\d+E\d+E\d+|(?:EP?|第)\d+\.\d+',
      caseSensitive: false,
    ).hasMatch(stem);
    final season =
        BilibiliEpisodeMatcher.season(stem) ??
        BilibiliEpisodeMatcher.season(parent);
    final targetSeason = BilibiliEpisodeMatcher.season(subject);
    final mismatch =
        season != null && subject.isNotEmpty && season != (targetSeason ?? 1);
    if (special || range || mismatch) {
      return CacheEpisodeFile(
        path,
        size,
        special
            ? '特别内容 · $name'
            : range
            ? '多集或分段 · $name'
            : '季数待确认 · $name',
      );
    }
    final bracket = RegExp(
      r'[\[【]\s*(\d{1,3})(?:v\d+)?\s*[\]】]|\s-\s*(\d{1,3})(?:v\d+)?(?=\s|\[|$)',
      caseSensitive: false,
    ).firstMatch(stem);
    final trailing = RegExp(
      r'(?:^|[\s._-])(\d{1,3})(?:v\d+)?(?=\s*(?:[\[【(]|END\b|$)|[._-](?:\d{3,4}p|BD|WEB))',
      caseSensitive: false,
    ).firstMatch(stem);
    final candidate = int.tryParse(
      bracket?.group(1) ?? bracket?.group(2) ?? trailing?.group(1) ?? '',
    );
    final number =
        BilibiliEpisodeMatcher.episode(stem) ??
        ([240, 360, 480, 576, 720, 264, 265].contains(candidate)
            ? 0
            : candidate ?? 0);
    if (number <= 0) {
      final plain = stem.trim().toLowerCase();
      final titled = catalog
          .where(
            (e) =>
                (e['type'] == null || e['type'] == 0) &&
                [e['name'], e['name_cn']].any(
                  (t) =>
                      t is String &&
                      t.trim().isNotEmpty &&
                      t.trim().toLowerCase() == plain,
                ),
          )
          .toList();
      if (titled.length == 1) {
        final ep = titled.single;
        final n = num.tryParse((ep['ep'] ?? ep['sort']).toString());
        if (n != null && n > 0 && n == n.toInt()) {
          return CacheEpisodeFile(
            path,
            size,
            TaskTitleParser.buildEpisodeDisplayLabel(
              episodeNumber: n.toInt(),
              episodeTitle: episodes.episodePlainTitle(ep),
            ),
            number: n.toInt(),
            episodeId: episodes.episodeId(ep),
          );
        }
      }
      return CacheEpisodeFile(path, size, '待确认 · $name');
    }
    final matches = catalog
        .where(
          (e) =>
              (num.tryParse((e['ep'] ?? e['sort']).toString()) == number) &&
              (e['type'] == null || e['type'] == 0),
        )
        .toList();
    final ep = matches.length == 1 ? matches.single : null;
    return CacheEpisodeFile(
      path,
      size,
      TaskTitleParser.buildEpisodeDisplayLabel(
        episodeNumber: number,
        episodeTitle: ep == null ? '' : episodes.episodePlainTitle(ep),
      ),
      number: number,
      episodeId: ep == null ? 0 : episodes.episodeId(ep),
    );
  }

  CacheEpisodeFile bind(
    int id,
    String text,
    int ep, {
    bool confirmed = false,
  }) => CacheEpisodeFile(
    path,
    size,
    text,
    episodeId: id,
    number: ep,
    manual: confirmed,
  );
  Map<String, dynamic> toJson() => {
    'path': path,
    'size': size,
    'label': label,
    'number': number,
    'id': episodeId,
    'manual': manual,
  };
  factory CacheEpisodeFile.fromJson(Map<String, dynamic> v) => CacheEpisodeFile(
    v['path'] as String,
    v['size'] as int,
    v['label'] as String,
    number: v['number'] as int,
    episodeId: v['id'] as int,
    manual: v['manual'] == true,
  );
}

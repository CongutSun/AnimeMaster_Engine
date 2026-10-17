class BilibiliPart {
  final int cid;
  final int page;
  final String title;
  final Duration duration;

  const BilibiliPart({
    required this.cid,
    required this.page,
    required this.title,
    required this.duration,
  });

  String get label => 'P$page · $title';
}

class BilibiliVideo {
  final String bvid;
  final String title;
  final List<BilibiliPart> parts;

  BilibiliVideo({
    required this.bvid,
    required this.title,
    required List<BilibiliPart> parts,
  }) : parts = List<BilibiliPart>.unmodifiable(parts);
}

class BilibiliPlayback {
  final BilibiliVideo video;
  final BilibiliPart part;
  final String qualityLabel;
  final int qualityId;
  final List<BilibiliQuality> qualities;

  const BilibiliPlayback({
    required this.video,
    required this.part,
    required this.qualityLabel,
    this.qualityId = 0,
    this.qualities = const <BilibiliQuality>[],
  });

  String get identity => 'bilibili:${video.bvid}:${part.cid}';

  String get pageUrl =>
      'https://www.bilibili.com/video/${video.bvid}?p=${part.page}';
}

class BilibiliQuality {
  final int id;
  final String label;
  const BilibiliQuality(this.id, this.label);
}

class BilibiliSearchHit {
  final String bvid;
  final String title;
  final String author;
  final Duration duration;
  final int score;
  const BilibiliSearchHit({
    required this.bvid,
    required this.title,
    required this.author,
    required this.duration,
    required this.score,
  });
  String get pageUrl => 'https://www.bilibili.com/video/$bvid';
}

class BilibiliSearchPage {
  final List<BilibiliSearchHit> videos;
  final int page;
  final int totalPages;
  const BilibiliSearchPage({
    required this.videos,
    required this.page,
    required this.totalPages,
  });
}

import 'package:animemaster/src/models/bilibili_video.dart';
import 'package:animemaster/src/models/online_episode_source.dart';
import 'package:animemaster/src/utils/bilibili_episode_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

OnlineEpisodeQuery _query(int episode, {String title = '测试动画'}) =>
    OnlineEpisodeQuery(
      bangumiSubjectId: 1,
      bangumiEpisodeId: episode + 100,
      subjectTitle: title,
      aliases: const <String>[],
      episodeNumber: episode,
      episodeTitle: '',
    );
BilibiliVideo _video(List<String> titles) => BilibiliVideo(
  bvid: 'BV1xx411c7mD',
  title: '合集',
  parts: <BilibiliPart>[
    for (int i = 0; i < titles.length; i++)
      BilibiliPart(
        cid: 100 + i,
        page: i + 1,
        title: titles[i],
        duration: const Duration(minutes: 24),
      ),
  ],
);

void main() {
  test(
    'a conflicting season in the collection title prevents a suggestion',
    () {
      final video = BilibiliVideo(
        bvid: 'BV1xx411c7mD',
        title: '测试动画 第一季',
        parts: _video(<String>['第2集']).parts,
      );
      expect(
        BilibiliEpisodeMatcher.suggest(video, _query(2, title: '测试动画 第二季')),
        isNull,
      );
    },
  );
  test('episode number comes from the title rather than P order', () {
    final video = _video(<String>['OP', '第1集', '第2集']);
    expect(BilibiliEpisodeMatcher.suggest(video, _query(2))!.page, 3);
  });
  test('seasons disambiguate the same episode number', () {
    final video = _video(<String>['S01E02', 'S02E02']);
    expect(BilibiliEpisodeMatcher.suggest(video, _query(2)), isNull);
    expect(
      BilibiliEpisodeMatcher.suggest(video, _query(2, title: '测试动画 第二季'))!.page,
      2,
    );
  });
  test('resolution, ranges and previews cannot become episode matches', () {
    expect(
      BilibiliEpisodeMatcher.suggest(
        _video(<String>['1080P', '1-12 合集', '第2集预告']),
        _query(2),
      ),
      isNull,
    );
  });
  test('duplicate episode titles require a manual choice', () {
    expect(
      BilibiliEpisodeMatcher.suggest(
        _video(<String>['第2集 A版', '第二话 B版']),
        _query(2),
      ),
      isNull,
    );
  });
  test('Chinese episode numbers are supported', () {
    expect(
      BilibiliEpisodeMatcher.suggest(
        _video(<String>['第十一话', '第十二话']),
        _query(12),
      )!.page,
      2,
    );
  });
}

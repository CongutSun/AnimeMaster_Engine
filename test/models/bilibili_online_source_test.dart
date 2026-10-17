import 'package:animemaster/src/models/bilibili_video.dart';
import 'package:animemaster/src/models/online_episode_source.dart';
import 'package:animemaster/src/models/playable_media.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Bilibili candidates retain page identity and require manual confirmation',
    () {
      const candidate = OnlineEpisodeSourceResult(
        title: '动画合集',
        pageUrl: 'https://www.bilibili.com/video/BV1xx411c7mD',
        mediaUrl: '',
        sourceName: 'Bilibili-UGC',
        snippet: '选择分 P 后播放',
        score: 80,
        bilibiliBvid: 'BV1xx411c7mD',
      );
      expect(candidate.canAutoPlay, isFalse);
      expect(candidate.verified, isFalse);
      expect(candidate.host, 'www.bilibili.com');
    },
  );

  test(
    'episode context retains the split audio and stable Bilibili identity',
    () {
      const part = BilibiliPart(
        cid: 10,
        page: 1,
        title: '第一话',
        duration: Duration(minutes: 24),
      );
      final video = BilibiliVideo(
        bvid: 'BV1xx411c7mD',
        title: '动画',
        parts: const <BilibiliPart>[part],
      );
      final original = PlayableMedia(
        title: '第一话',
        url: 'https://cdn.example/v',
        audioUrl: 'https://cdn.example/a',
        bilibili: BilibiliPlayback(
          video: video,
          part: part,
          qualityLabel: '480P',
          qualityId: 32,
        ),
      );
      final associated = original.withEpisodeContext(
        subjectTitle: '动画',
        episodeLabel: '第1集',
        bangumiSubjectId: 1,
        bangumiEpisodeId: 10,
      );
      expect(associated.bilibili!.identity, original.bilibili!.identity);
      expect(associated.audioUrl, original.audioUrl);
      expect(associated.bangumiEpisodeId, 10);
    },
  );
}

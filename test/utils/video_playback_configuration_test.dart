import 'package:animemaster/src/models/bilibili_video.dart';
import 'package:animemaster/src/models/playable_media.dart';
import 'package:animemaster/src/utils/video_playback_configuration.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const part = BilibiliPart(
    cid: 1,
    page: 1,
    title: '视频',
    duration: Duration(seconds: 60),
  );
  final video = BilibiliVideo(
    bvid: 'BV1yspC6sEne',
    title: '测试视频',
    parts: const <BilibiliPart>[part],
  );
  final media = PlayableMedia(
    title: '测试视频',
    url: 'https://cdn.example/video',
    bilibili: BilibiliPlayback(video: video, part: part, qualityLabel: '480P'),
  );

  test('Android Bilibili uses software decoding and retains GPU rendering', () {
    final configuration = videoPlaybackConfiguration(
      media,
      platform: TargetPlatform.android,
    );
    expect(configuration.hwdec, 'no');
    expect(configuration.enableHardwareAcceleration, isTrue);
    expect(configuration.vo, isNull);
  });

  test(
    'local media and other platforms keep the default decoding configuration',
    () {
      final local = PlayableMedia(title: '本地视频', url: '/video.mp4');
      expect(
        videoPlaybackConfiguration(
          local,
          platform: TargetPlatform.android,
        ).hwdec,
        isNull,
      );
      for (final platform in <TargetPlatform>[
        TargetPlatform.windows,
        TargetPlatform.iOS,
      ]) {
        expect(
          videoPlaybackConfiguration(media, platform: platform).hwdec,
          isNull,
        );
      }
    },
  );
}

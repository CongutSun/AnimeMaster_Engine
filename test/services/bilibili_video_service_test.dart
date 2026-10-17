import 'dart:convert';
import 'dart:typed_data';

import 'package:animemaster/src/models/bilibili_video.dart';
import 'package:animemaster/src/services/bilibili_video_service.dart';
import 'package:animemaster/src/utils/playback_progress_store.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) handle;
  _Adapter(this.handle);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => handle(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _reply(Map<String, dynamic> json) => ResponseBody.fromString(
  jsonEncode(json),
  200,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>['application/json'],
  },
);

const String _bvid = 'BV1xx411c7mD';
const String _img = '7cd084941338484aae1ad9425b84077c';
const String _sub = '4932caff0ff746eab6f01bf08b70ac45';
Map<String, dynamic> _view() => <String, dynamic>{
  'code': 0,
  'data': <String, dynamic>{
    'title': '测试视频',
    'pages': <Map<String, dynamic>>[
      <String, dynamic>{'cid': 101, 'page': 1, 'part': '开场', 'duration': 60},
      <String, dynamic>{'cid': 202, 'page': 2, 'part': '正片', 'duration': 600},
    ],
  },
};
Map<String, dynamic> _nav() => <String, dynamic>{
  'code': -101,
  'data': <String, dynamic>{
    'wbi_img': <String, String>{
      'img_url': 'https://i0.hdslb.com/bfs/wbi/$_img.png',
      'sub_url': 'https://i0.hdslb.com/bfs/wbi/$_sub.png',
    },
  },
};
Map<String, dynamic> _dash() => <String, dynamic>{
  'code': 0,
  'data': <String, dynamic>{
    'dash': <String, dynamic>{
      'video': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 32,
          'codecid': 7,
          'baseUrl': 'https://cdn.example/480',
        },
        <String, dynamic>{
          'id': 112,
          'codecid': 7,
          'baseUrl': 'https://cdn.example/plus',
        },
        <String, dynamic>{
          'id': 80,
          'codecid': 12,
          'baseUrl': 'https://cdn.example/hevc',
        },
        <String, dynamic>{
          'id': 80,
          'codecid': 7,
          'base_url': 'https://cdn.example/avc',
        },
      ],
      'audio': <Map<String, dynamic>>[
        <String, dynamic>{
          'bandwidth': 64000,
          'baseUrl': 'https://cdn.example/low',
        },
        <String, dynamic>{
          'bandwidth': 192000,
          'base_url': 'https://cdn.example/audio',
        },
      ],
    },
  },
};

void main() {
  late List<RequestOptions> requests;
  late Map<String, dynamic> playResponse;
  late BilibiliVideoService service;
  setUp(() {
    requests = <RequestOptions>[];
    playResponse = _dash();
    final Dio dio = Dio()
      ..httpClientAdapter = _Adapter((RequestOptions options) {
        requests.add(options);
        return _reply(switch (options.uri.path) {
          '/x/web-interface/view' => _view(),
          '/x/web-interface/nav' => _nav(),
          _ => playResponse,
        });
      });
    service = BilibiliVideoService(
      dio: dio,
      cookieProvider: () async => '',
      clock: () => DateTime.fromMillisecondsSinceEpoch(1702204169000),
    );
  });

  test(
    'explicit quality choice uses an available AVC stream and reports actual options',
    () async {
      final video = await service.loadVideo(_bvid);
      final media = await service.resolvePart(
        video,
        video.parts.first,
        preferredQuality: 32,
      );
      expect(media.url, 'https://cdn.example/480');
      expect(media.bilibili!.qualityId, 32);
      expect(media.bilibili!.qualities.map((item) => item.id), <int>[80, 32]);
    },
  );

  test(
    'authenticated API calls never attach session cookies to playback headers',
    () async {
      final authRequests = <RequestOptions>[];
      final dio = Dio()
        ..httpClientAdapter = _Adapter((options) {
          authRequests.add(options);
          return _reply(switch (options.uri.path) {
            '/x/web-interface/view' => _view(),
            '/x/web-interface/nav' => _nav(),
            _ => _dash(),
          });
        });
      final signedIn = BilibiliVideoService(
        dio: dio,
        cookieProvider: () async => 'SESSDATA=test',
      );
      final video = await signedIn.loadVideo(_bvid);
      final media = await signedIn.resolvePart(video, video.parts.first);
      expect(
        authRequests.every(
          (request) => request.headers['Cookie'] == 'SESSDATA=test',
        ),
        isTrue,
      );
      expect(media.headers!.containsKey('Cookie'), isFalse);
      expect(dio.options.headers.containsKey('Cookie'), isFalse);
    },
  );

  test(
    'search signs requests, decodes titles and ranks long videos without discarding short ones',
    () async {
      final searchRequests = <RequestOptions>[];
      final dio = Dio()
        ..httpClientAdapter = _Adapter((options) {
          searchRequests.add(options);
          return _reply(switch (options.uri.path) {
            '/x/web-interface/nav' => _nav(),
            '/x/frontend/finger/spi' => <String, dynamic>{
              'code': 0,
              'data': <String, String>{'b_3': 'visitor-id'},
            },
            _ => <String, dynamic>{
              'code': 0,
              'data': <String, dynamic>{
                'numPages': 2,
                'result': <Map<String, String>>[
                  <String, String>{
                    'bvid': _bvid,
                    'title': '<em class="keyword">动画</em> 合集 &amp; 正片',
                    'duration': '1:20:00',
                    'author': '作者',
                  },
                  <String, String>{
                    'bvid': 'BV1yspC6sEne',
                    'title': '动画 短篇',
                    'duration': '03:00',
                    'author': '作者',
                  },
                  <String, String>{
                    'bvid': 'BV1GJ411x7h7',
                    'title': '动画 解说',
                    'duration': '30:00',
                    'author': '作者',
                  },
                ],
              },
            },
          });
        });
      final search = BilibiliVideoService(
        dio: dio,
        cookieProvider: () async => '',
      );
      final result = await search.searchVideos('动画');
      expect(result.videos, hasLength(3));
      expect(result.videos.first.title, '动画 合集 & 正片');
      expect(result.videos.first.duration, const Duration(minutes: 80));
      expect(result.videos.last.title, '动画 解说');
      expect(searchRequests.last.uri.queryParameters['keyword'], '动画');
      expect(searchRequests.last.uri.queryParameters['w_rid'], isNotEmpty);
      expect(searchRequests.last.headers['Cookie'], 'buvid3=visitor-id');
    },
  );

  test(
    'accepts BV and video links while rejecting unrelated hosts and short links',
    () {
      expect(BilibiliVideoService.parseBvid(' $_bvid '), _bvid);
      expect(
        BilibiliVideoService.parseBvid(
          'https://www.bilibili.com/video/$_bvid/?p=2',
        ),
        _bvid,
      );
      for (final String value in <String>[
        'https://evil.example/video/$_bvid',
        'https://www.bilibili.com.evil.example/video/$_bvid',
        'https://b23.tv/abc',
        'BV123',
      ]) {
        expect(
          () => BilibiliVideoService.parseBvid(value),
          throwsA(isA<BilibiliVideoException>()),
        );
      }
    },
  );

  test('signs timestamp in key order and encodes Chinese and spaces', () {
    final Map<String, String> input = <String, String>{
      'zab': '1919810',
      'bar': '514',
      'foo': '114',
    };
    const String canonical = 'bar=514&foo=114&wts=1702204169&zab=1919810';
    const String mixin = 'ea1db124af3c7062474693fa704f4ff8';
    expect(
      BilibiliWbiSigner.sign(
        input,
        imgKey: _img,
        subKey: _sub,
        timestamp: 1702204169,
      ),
      '$canonical&w_rid=${md5.convert(utf8.encode(canonical + mixin))}',
    );
    expect(input.containsKey('wts'), isFalse);
    expect(
      BilibiliWbiSigner.sign(
        <String, String>{'keyword': "中 文!'()*"},
        imgKey: _img,
        subKey: _sub,
        timestamp: 1,
      ),
      startsWith('keyword=%E4%B8%AD%20%E6%96%87&wts=1&'),
    );
  });

  test(
    'selected P uses its cid, preserves audio and selects 1080P AVC regardless of array order',
    () async {
      final BilibiliVideo video = await service.loadVideo(_bvid);
      expect(video.parts.map((BilibiliPart p) => p.cid), <int>[101, 202]);
      final media = await service.resolvePart(video, video.parts[1]);
      expect(requests.last.uri.queryParameters['cid'], '202');
      expect(requests.last.uri.queryParameters['w_rid'], isNotEmpty);
      expect(media.url, 'https://cdn.example/avc');
      expect(media.audioUrl, 'https://cdn.example/audio');
      expect(media.bilibili!.part.cid, 202);
      expect(media.bilibili!.qualityLabel, '1080P');
      expect(media.headers!['Referer'], 'https://www.bilibili.com/');
      expect(media.headers!.containsKey('Cookie'), isFalse);
    },
  );

  test(
    'guest lower quality is used and key cache survives P changes',
    () async {
      final BilibiliVideo video = await service.loadVideo(_bvid);
      (playResponse['data']['dash']['video'] as List).removeRange(1, 4);
      final first = await service.resolvePart(video, video.parts.first);
      final second = await service.resolvePart(video, video.parts.last);
      expect(first.bilibili!.qualityLabel, '480P');
      expect(second.bilibili!.qualityLabel, '480P');
      expect(
        requests.where((RequestOptions o) => o.uri.path.endsWith('/nav')),
        hasLength(1),
      );
      expect(
        PlaybackProgressStore.keyFor(first),
        isNot(PlaybackProgressStore.keyFor(second)),
      );
      playResponse['data']['dash']['video'][0]['baseUrl'] =
          'https://other.example/renewed';
      final refreshed = await service.resolvePart(video, video.parts.first);
      expect(
        PlaybackProgressStore.keyFor(refreshed),
        PlaybackProgressStore.keyFor(first),
      );
    },
  );

  test(
    'lower quality AVC is preferred over higher quality HEVC or AV1',
    () async {
      final video = await service.loadVideo(_bvid);
      playResponse['data']['dash']['video'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 80,
          'codecid': 12,
          'baseUrl': 'https://cdn.example/hevc',
        },
        <String, dynamic>{
          'id': 80,
          'codecid': 13,
          'baseUrl': 'https://cdn.example/av1',
        },
        <String, dynamic>{
          'id': 32,
          'codecid': 7,
          'baseUrl': 'https://cdn.example/avc',
        },
      ];
      final media = await service.resolvePart(video, video.parts.first);
      expect(media.url, 'https://cdn.example/avc');
      expect(media.bilibili!.qualityLabel, '480P');
    },
  );

  test(
    'HEVC-only video is rejected and AVC codec string can identify missing codecid',
    () async {
      final video = await service.loadVideo(_bvid);
      playResponse['data']['dash']['video'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 80,
          'codecid': 12,
          'baseUrl': 'https://cdn.example/hevc',
        },
      ];
      await expectLater(
        service.resolvePart(video, video.parts.first),
        throwsA(isA<BilibiliVideoException>()),
      );
      playResponse['data']['dash']['video'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 32,
          'codecs': 'avc1.640033',
          'baseUrl': 'https://cdn.example/avc',
        },
      ];
      expect(
        (await service.resolvePart(video, video.parts.first)).url,
        'https://cdn.example/avc',
      );
    },
  );

  test(
    'missing DASH audio and denied HTTP 200 responses never become playable media',
    () async {
      final BilibiliVideo video = await service.loadVideo(_bvid);
      playResponse['data']['dash']['audio'] = <dynamic>[];
      await expectLater(
        service.resolvePart(video, video.parts.first),
        throwsA(isA<BilibiliVideoException>()),
      );
      playResponse = <String, dynamic>{'code': -10403, 'data': null};
      await expectLater(
        service.resolvePart(video, video.parts.first),
        throwsA(isA<BilibiliVideoException>()),
      );
    },
  );

  test(
    'risk challenge refreshes keys once and then reports verification required',
    () async {
      final BilibiliVideo video = await service.loadVideo(_bvid);
      playResponse = <String, dynamic>{
        'code': 0,
        'data': <String, String>{'v_voucher': 'challenge'},
      };
      await expectLater(
        service.resolvePart(video, video.parts.first),
        throwsA(
          isA<BilibiliVideoException>().having(
            (e) => e.message,
            'message',
            contains('验证'),
          ),
        ),
      );
      expect(
        requests.where((RequestOptions o) => o.uri.path.endsWith('/nav')),
        hasLength(2),
      );
      expect(
        requests.where((RequestOptions o) => o.uri.path.endsWith('/playurl')),
        hasLength(2),
      );
    },
  );

  test(
    'muxed MP4 does not attach a second audio and foreign cid is rejected',
    () async {
      final BilibiliVideo video = await service.loadVideo(_bvid);
      playResponse = <String, dynamic>{
        'code': 0,
        'data': <String, dynamic>{
          'quality': 32,
          'durl': <Map<String, String>>[
            <String, String>{'url': 'https://cdn.example/muxed.mp4'},
          ],
        },
      };
      final media = await service.resolvePart(video, video.parts.first);
      expect(media.audioUrl, isNull);
      final int count = requests.length;
      await expectLater(
        service.resolvePart(
          video,
          const BilibiliPart(
            cid: 999,
            page: 3,
            title: 'unknown',
            duration: Duration.zero,
          ),
        ),
        throwsA(isA<BilibiliVideoException>()),
      );
      expect(requests.length, count);
    },
  );
}

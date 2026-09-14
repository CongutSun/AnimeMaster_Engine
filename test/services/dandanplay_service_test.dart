import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:animemaster/src/models/dandanplay_models.dart';
import 'package:animemaster/src/services/dandanplay_cache.dart';
import 'package:animemaster/src/services/dandanplay_service.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Adapter implements HttpClientAdapter {
  Adapter(this.handle);
  final Future<ResponseBody> Function(RequestOptions) handle;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handle(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody reply(Map<String, dynamic> data, [int status = 200]) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
const match = DandanplayMatchResult(
  episodeId: 690001,
  animeId: 69,
  animeTitle: '测试动画',
  episodeTitle: '第1话',
  shift: 2,
);
Map<String, dynamic> comments() => {
  'comments': [
    {'cid': 1, 'p': '3.5,1,16777215,user', 'm': '你好'},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DandanplayCache cache;
  late List<RequestOptions> requests;
  late Future<ResponseBody> Function(RequestOptions) handler;
  late DandanplayService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp(
      'animemaster-danmaku-test-',
    );
    cache = DandanplayCache(directory: () async => directory);
    requests = [];
    handler = (_) async => reply(comments());
    final dio = Dio()
      ..httpClientAdapter = Adapter((options) {
        requests.add(options);
        return handler(options);
      });
    service = DandanplayService(dio: dio, cache: cache);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'default gateway reads and persists shifted comments without application secrets',
    () async {
      final result = await service.loadDanmakuFromMatch(match);
      expect(
        result.comments.single.appearAt,
        const Duration(milliseconds: 5500),
      );
      expect(result.source, 'dandanplay');
      expect(result.isStale, isFalse);
      expect(requests.single.uri.host, 'auth.congutsun.com');
      expect(requests.single.headers.containsKey('X-AppId'), isFalse);
      final other = DandanplayService(cache: cache);
      expect(
        (await other.loadDanmakuFromMatch(match)).comments.single.text,
        '你好',
      );
      expect(requests.length, 1);
    },
  );
  test(
    'expired comment cache is explicitly marked stale after network failure',
    () async {
      await cache.write(
        'gateway-v1:comments:690001',
        comments(),
        const Duration(seconds: -1),
      );
      handler = (_) async => reply({'errorMessage': 'unavailable'}, 503);
      expect((await service.loadDanmakuFromMatch(match)).isStale, isTrue);
    },
  );
  test(
    'permission denial does not expose cached comments as a successful read',
    () async {
      await cache.write(
        'gateway-v1:comments:690001',
        comments(),
        const Duration(seconds: -1),
      );
      handler = (_) async => reply({'errorMessage': 'denied'}, 403);
      await expectLater(
        service.loadDanmakuFromMatch(match),
        throwsA(
          isA<DandanplayException>().having((e) => e.status, 'status', 403),
        ),
      );
    },
  );
  test('business failure returned as HTTP 200 is an error', () async {
    handler = (_) async => reply({'success': false, 'errorCode': 7});
    await expectLater(
      service.details('1'),
      throwsA(isA<DandanplayException>()),
    );
  });
  test(
    'Bangumi mapping selects episode number, not Bangumi ID as a comment ID',
    () async {
      handler = (o) async {
        if (o.uri.path.contains('/bgmtv/')) {
          return reply({
            'bangumi': {
              'animeId': 69,
              'animeTitle': '测试动画',
              'episodes': [
                {
                  'episodeId': 690001,
                  'episodeNumber': '1',
                  'episodeTitle': '第1话',
                },
                {'episodeId': 690002, 'episodeNumber': '2'},
              ],
            },
          });
        }
        return reply(comments());
      };
      final result = await service.loadDanmaku(
        displayTitle: '测试动画',
        bangumiSubjectId: 975,
        episodeLabel: '第1话',
      );
      expect(result.match.episodeId, 690001);
      expect(requests.map((r) => r.uri.path), [
        '/dandanplay/api/v2/bangumi/bgmtv/975',
        '/dandanplay/api/v2/comment/690001',
      ]);
    },
  );
  test(
    'multiple search results require explicit selection and never load first comment pool',
    () async {
      handler = (_) async => reply({
        'animes': [
          {
            'animeId': 69,
            'animeTitle': '测试动画',
            'episodes': [
              {'episodeId': 1},
              {'episodeId': 2},
            ],
          },
        ],
      });
      await expectLater(
        service.loadDanmaku(displayTitle: '测试动画', episodeLabel: '1'),
        throwsA(isA<DandanplayMatchRequired>()),
      );
      expect(requests.length, 1);
      expect(requests.single.queryParameters['v2'], isTrue);
    },
  );
  test(
    'manual match survives service recreation without another search',
    () async {
      await service.rememberManualMatch(
        displayTitle: 'video',
        localFilePath: '',
        subjectTitle: '',
        episodeLabel: '',
        match: match,
      );
      final result = await service.loadDanmaku(displayTitle: 'video');
      expect(result.match.episodeId, match.episodeId);
      expect(requests.single.uri.path, '/dandanplay/api/v2/comment/690001');
      final other = DandanplayService(cache: cache);
      expect(
        (await other.loadDanmaku(displayTitle: 'video')).match.episodeId,
        match.episodeId,
      );
    },
  );
  test(
    'file matching hashes only first 16 MiB and excludes extension',
    () async {
      final bytes = Uint8List(16 * 1024 * 1024 + 1)..last = 7;
      final file = File('${directory.path}/episode.mkv');
      await file.writeAsBytes(bytes);
      handler = (o) async {
        if (o.uri.path.endsWith('/match')) {
          expect(o.data['fileName'], 'episode');
          expect(o.data['fileSize'], bytes.length);
          expect(
            o.data['fileHash'],
            md5.convert(bytes.sublist(0, 16 * 1024 * 1024)).toString(),
          );
          return reply({
            'isMatched': true,
            'matches': [match.toJson()],
          });
        }
        return reply(comments());
      };
      expect(
        (await service.loadDanmaku(
          displayTitle: 'video',
          localFilePath: file.path,
          fileReady: true,
        )).match.episodeId,
        690001,
      );
      expect(requests.length, 2);
    },
  );
  test('incomplete or online media is not hashed', () async {
    handler = (_) async => reply({'animes': []});
    await expectLater(
      service.loadDanmaku(
        displayTitle: 'video',
        localFilePath: '${directory.path}/partial.mkv',
      ),
      throwsA(isA<DandanplayException>()),
    );
    expect(requests.single.uri.path, '/dandanplay/api/v2/search/episodes');
  });
  test('search cache hits do not extend original expiration', () async {
    handler = (_) async => reply({'animes': []});
    await service.searchEpisodeCandidates(animeKeyword: '测试');
    final file = (await Directory(
      '${directory.path}/dandanplay',
    ).list().toList()).whereType<File>().single;
    final original = await file.readAsString();
    await service.searchEpisodeCandidates(animeKeyword: '测试');
    expect(await file.readAsString(), original);
    expect(requests.length, 1);
  });
  test(
    'sending corrects shift, keeps request ID, and invalidates comment cache',
    () async {
      await cache.write(
        'gateway-v1:comments:690001',
        comments(),
        const Duration(minutes: 5),
      );
      handler = (o) async {
        expect(o.data['time'], 8);
        expect(o.data['comment'], '你好');
        expect(o.headers['X-Request-Id'], 'a' * 32);
        expect(o.headers['X-Installation-Id'], hasLength(32));
        return reply({'success': true});
      };
      await service.sendComment(
        match,
        text: ' 你好 ',
        position: const Duration(seconds: 10),
        requestId: 'a' * 32,
      );
      expect(await cache.read('gateway-v1:comments:690001'), isNull);
    },
  );
  test('episode parser does not treat resolution as an episode', () {
    expect(
      service.buildSuggestedEpisodeKeyword(displayTitle: '[Team] 测试 [1080p]'),
      '',
    );
    expect(
      service.buildSuggestedEpisodeKeyword(displayTitle: '测试 S01E03 [1080p]'),
      '3',
    );
    expect(
      service.buildSuggestedEpisodeKeyword(displayTitle: '测试 - 02 [1080p]'),
      '2',
    );
    expect(
      service.buildSuggestedEpisodeKeyword(
        displayTitle: '测试',
        episodeLabel: 'S01',
      ),
      'S1',
    );
  });
  test('invalid numeric comments cannot crash parsing', () {
    expect(
      DandanplayComment.fromJson({
        'p': 'NaN,1,1,u',
        'm': 'x',
      }).appearAt.inSeconds,
      greaterThan(86400),
    );
    expect(DandanplayMatchResult.fromJson({'shift': 'Infinity'}).shift, 0);
  });
  test(
    'discovery and details cache locally and use adult-content filter',
    () async {
      handler = (_) async => reply({'bangumiList': []});
      await service.discovery(category: 'rising', period: 'month');
      await service.discovery(category: 'rising', period: 'month');
      expect(requests.length, 1);
      expect(
        requests.single.uri.path,
        '/dandanplay/api/v2/trending/all/rising/month',
      );
      expect(requests.single.queryParameters['filterAdultContent'], isTrue);
    },
  );
  test('disk cache prunes older entries and honors expiry', () async {
    for (var i = 0; i < 66; i++) {
      await cache.write('key$i', {'value': i}, const Duration(minutes: 1));
    }
    expect(await Directory('${directory.path}/dandanplay').list().length, 64);
    await cache.write('expired', {'value': 1}, const Duration(seconds: -1));
    expect(await cache.read('expired'), isNull);
    expect(await cache.read('expired', allowExpired: true), {'value': 1});
  });
}

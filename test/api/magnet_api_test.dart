import 'dart:async';
import 'dart:typed_data';
import 'package:animemaster/src/api/dio_client.dart';
import 'package:animemaster/src/models/rss_resource.dart';
import 'package:animemaster/src/api/magnet_api.dart';
import 'package:animemaster/src/services/rss_feed_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FeedAdapter implements HttpClientAdapter {
  final slow = Completer<void>();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    if (options.uri.host == 'slow.example') await slow.future;
    final bad = options.uri.host == 'slow.example';
    return ResponseBody.fromString(
      bad
          ? '<html>upstream error</html>'
          : '<rss version="2.0"><channel><title>Test</title><item><title>Test EP06 1080p</title><enclosure url="https://files.example/file.torrent" type="application/x-bittorrent" length="123"/></item></channel></rss>',
      200,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FlakyFeed extends RssFeedService {
  int calls = 0;
  bool offline = false;
  @override
  Future<RssFeedSnapshot> fetch(String url, {bool force = false}) async {
    calls++;
    if (offline) throw const RssFeedException('离线');
    return RssFeedSnapshot(
      title: '来源',
      fetchedAt: DateTime.now(),
      items: const [
        RssResource(
          id: 'ep',
          title: '动画 EP01',
          torrent: 'https://source.test/episode.torrent',
        ),
      ],
    );
  }
}

void main() {
  test('同一 BTIH 的十六进制与 Base32 入口合并，同名不同种保留', () {
    final a = '0' * 40, b = '1' * 40;
    final grouped = MagnetApi.groupResults([
      {'source': 'A', 'title': '动画', 'torrent': 'https://a.test/$a.torrent'},
      {
        'source': 'B',
        'title': '动画',
        'torrent': 'https://b.test/ep.torrent',
        'magnet': 'magnet:?xt=urn:btih:${'A' * 32}',
      },
      {'source': 'C', 'title': '动画', 'magnet': 'magnet:?xt=urn:btih:$b'},
    ]);
    expect(grouped.length, 2);
    expect(grouped.first['source'], 'A / B');
    expect(
      MagnetApi.routes(grouped.first),
      contains('https://b.test/ep.torrent'),
    );
  });
  test('失败时保留同条件最近结果，连续失败进入冷却，不串关键词', () async {
    final feed = _FlakyFeed();
    Future<List<Map<String, String>>> search(String term) =>
        MagnetApi.searchTorrents(
          keyword: term,
          selectedSources: [
            {'name': '断线测试', 'url': 'https://cooldown.test/search?q={keyword}'},
          ],
          feedService: feed,
        );
    expect((await search('a')).single.containsKey('cachedAt'), false);
    feed.offline = true;
    expect((await search('a')).single['cachedAt'], isNotEmpty);
    expect(await search('b'), isEmpty);
    expect((await search('a')).single['cachedAt'], isNotEmpty);
    expect(feed.calls, 3);
  });
  test('指定集数也能找到明确覆盖该集的合集', () async {
    final service = _PackFeed();
    Future<List<Map<String, String>>> run(int ep) => MagnetApi.searchTorrents(
      keyword: '动画',
      selectedSources: [
        {'name': 'pack', 'url': 'https://pack.test/?q={keyword}'},
      ],
      feedService: service,
      targetEpisodeNumber: ep,
    );
    expect(await run(4), hasLength(1));
    expect(await run(14), isEmpty);
  });
  test('Nyaa RSS infoHash 能作为磁链备用入口', () {
    final hash = 'a' * 40;
    final feed = RssFeedService.parse(
      '<rss xmlns:nyaa="https://nyaa.si/xmlns/nyaa"><channel><item><title>动画</title><link>https://nyaa.si/download/1.torrent</link><nyaa:infoHash>$hash</nyaa:infoHash></item></channel></rss>',
      Uri.parse('https://nyaa.si/'),
    );
    expect(feed.items.single.magnet, 'magnet:?xt=urn:btih:$hash');
  });
  test(
    'publishes fast source results before slow failures and preserves partial success',
    () async {
      final dio = DioClient().dio;
      final original = dio.httpClientAdapter;
      final adapter = _FeedAdapter();
      dio.httpClientAdapter = adapter;
      addTearDown(() => dio.httpClientAdapter = original);
      final partial = Completer<void>();
      final statuses = <String, bool>{};
      final search = MagnetApi.searchTorrents(
        feedService: RssFeedService(dio: Dio()..httpClientAdapter = adapter),
        keyword: 'test',
        selectedSources: [
          {'name': 'fast', 'url': 'https://fast.example/rss'},
          {'name': 'slow', 'url': 'https://slow.example/rss'},
        ],
        onResults: (items) {
          if (items.isNotEmpty && !partial.isCompleted) partial.complete();
        },
        onSourceComplete: (name, success) => statuses[name] = success,
      );
      await partial.future;
      expect(adapter.slow.isCompleted, false);
      adapter.slow.complete();
      final results = await search;
      expect(results.single['torrent'], 'https://files.example/file.torrent');
      expect(statuses, {'fast': true, 'slow': false});
    },
  );
}

class _PackFeed extends RssFeedService {
  @override
  Future<RssFeedSnapshot> fetch(String url, {bool force = false}) async =>
      RssFeedSnapshot(
        title: '合集',
        fetchedAt: DateTime.now(),
        items: const [
          RssResource(
            id: 'pack',
            title: '动画 [01-12] [1080p]',
            torrent: 'https://pack.test/show.torrent',
          ),
        ],
      );
}

import 'dart:typed_data';
import 'package:animemaster/src/api/magnet_api.dart';
import 'package:animemaster/src/models/rss_resource.dart';
import 'package:animemaster/src/services/rss_feed_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const hash = '0123456789012345678901234567890123456789';
const feedXml =
    '<rss version="2.0"><channel><title>资源订阅</title>'
    '<item><guid>one</guid><title>[字幕组] 测试番剧 - 06 [1080p]</title>'
    '<pubDate>Wed, 16 Sep 2026 10:00:00 GMT</pubDate>'
    '<enclosure url="/download/one.torrent" type="application/x-bittorrent"/></item>'
    '<item><title>Other Anime EP07</title><link>magnet:?xt=urn:btih:$hash</link></item>'
    '</channel></rss>';

class FeedAdapter implements HttpClientAdapter {
  int calls = 0, status = 200;
  String body = feedXml;
  RequestOptions? last;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    calls++;
    last = options;
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        'etag': ['"v1"'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('RSS numeric timezone and Atom XHTML content', () {
    final feed = RssFeedService.parse(
      '<feed><entry><title>Test</title><published>Wed, 16 Sep 2026 18:00:00 +0800</published><content type="xhtml"><div><a href="https://feed.example/file.torrent">Download</a></div></content></entry></feed>',
      Uri.parse('https://feed.example/rss'),
    );
    expect(feed.items.single.publishedAt, DateTime.utc(2026, 9, 16, 10));
    expect(feed.items.single.torrent, 'https://feed.example/file.torrent');
  });
  final base = Uri.parse('https://feed.example/private/rss?token=test-only');
  test('RSS enclosure, publication date, title and magnet', () {
    final feed = RssFeedService.parse(feedXml, base);
    expect(feed.title, '资源订阅');
    expect(feed.items.length, 2);
    expect(
      feed.items.first.torrent,
      'https://feed.example/download/one.torrent',
    );
    expect(feed.items.first.publishedAt, DateTime.utc(2026, 9, 16, 10));
    expect(feed.items.last.magnet, 'magnet:?xt=urn:btih:$hash');
  });
  test('Atom namespaces and description hyperlinks are supported', () {
    final feed = RssFeedService.parse(
      '''<feed xmlns="http://www.w3.org/2005/Atom"><title>Atom</title>
      <entry><id>urn:one</id><title>Anime EP03</title><updated>2026-09-16T10:00:00Z</updated>
      <link rel="enclosure" href="/file.torrent" type="application/x-bittorrent"/>
      <content type="html">&lt;a href="magnet:?xt=urn:btih:$hash&amp;amp;dn=Test"&gt;下载&lt;/a&gt;</content></entry></feed>''',
      base,
    );
    expect(feed.items.single.torrent, 'https://feed.example/file.torrent');
    expect(feed.items.single.magnet, contains(hash));
    expect(feed.items.single.publishedAt, isNotNull);
  });
  test('description plain magnet and duplicate hashes collapse', () {
    final feed = RssFeedService.parse(
      '''<rss><channel><item><title>A</title><description><![CDATA[magnet:?xt=urn:btih:$hash&dn=A]]></description></item>
      <item><title>B</title><link>magnet:?xt=urn:btih:$hash&amp;dn=B</link></item></channel></rss>''',
      base,
    );
    expect(feed.items.length, 1);
  });
  test(
    'rejects HTML and external entities and does not treat detail links as torrents',
    () {
      expect(
        () => RssFeedService.parse('<html/>', base),
        throwsA(isA<RssFeedException>()),
      );
      expect(
        () => RssFeedService.parse(
          '<!DOCTYPE rss [<!ENTITY x SYSTEM "file:///private">]><rss/>',
          base,
        ),
        throwsA(isA<RssFeedException>()),
      );
      final feed = RssFeedService.parse(
        '<rss><channel><item><title>A</title><link>https://feed.example/post/1</link></item></channel></rss>',
        base,
      );
      expect(feed.items.single.downloadUrl, isEmpty);
    },
  );
  test(
    'type detection and validation do not accept insecure or credential URLs',
    () {
      expect(isSubscriptionSource({'url': base.toString()}), isTrue);
      expect(
        isSubscriptionSource({'url': 'https://a.example?q={keyword}'}),
        isFalse,
      );
      for (final url in [
        'http://a.example/rss',
        'https://user:pass@a.example/rss',
        'https://a.example/rss#token',
      ]) {
        expect(validateRssUrl(url), isNotNull);
      }
      expect(validateRssUrl(base.toString(), search: true), isNotNull);
    },
  );
  test(
    'search matches aliases and ignores punctuation without matching empty titles',
    () {
      expect(
        RssFeedService.matchesTitle('[组] Test-Anime EP05', ['Test Anime']),
        isTrue,
      );
      expect(
        RssFeedService.matchesTitle('测试番剧 第5集', ['Other', '测试番剧']),
        isTrue,
      );
      expect(RssFeedService.matchesTitle('Other', ['', '测试番剧']), isFalse);
    },
  );
  test('coalesces network requests and revalidates cached response', () async {
    final adapter = FeedAdapter();
    final service = RssFeedService(dio: Dio()..httpClientAdapter = adapter);
    final feeds = await Future.wait([
      service.fetch(base.toString()),
      service.fetch(base.toString()),
    ]);
    expect(adapter.calls, 1);
    expect(feeds.first.items.length, 2);
    await service.fetch(base.toString());
    expect(adapter.calls, 1);
    adapter.status = 304;
    final again = await service.fetch(base.toString(), force: true);
    expect(again.items.length, 2);
    expect(adapter.last!.headers['If-None-Match'], '"v1"');
    expect(adapter.last!.followRedirects, isFalse);
  });
  test(
    'network errors never reveal private address and oversized bodies fail',
    () async {
      final adapter = FeedAdapter()..status = 403;
      final service = RssFeedService(dio: Dio()..httpClientAdapter = adapter);
      await expectLater(
        service.fetch(base.toString()),
        throwsA(
          isA<RssFeedException>().having(
            (e) => e.toString(),
            'redacted',
            isNot(contains('test-only')),
          ),
        ),
      );
      adapter
        ..status = 200
        ..body = 'a' * (RssFeedService.maxBytes + 1);
      await expectLater(
        service.fetch(base.toString()),
        throwsA(isA<RssFeedException>()),
      );
    },
  );
  test(
    'fixed feed search applies keyword, aliases, quality and episode locally',
    () async {
      final adapter = FeedAdapter();
      final service = RssFeedService(dio: Dio()..httpClientAdapter = adapter);
      final results = await MagnetApi.searchTorrents(
        keyword: 'Japanese Name',
        aliases: ['测试番剧'],
        quality: '1080p',
        targetEpisodeNumber: 6,
        selectedSources: [
          {'name': 'test', 'url': base.toString()},
        ],
        feedService: service,
      );
      expect(results.length, 1);
      expect(results.single['title'], contains('测试番剧'));
      expect(adapter.last!.uri, base);
      final none = await MagnetApi.searchTorrents(
        keyword: '不存在',
        selectedSources: [
          {'url': base.toString()},
        ],
        feedService: service,
      );
      expect(none, isEmpty);
      expect(adapter.calls, 1);
    },
  );
}

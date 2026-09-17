import 'dart:async';
import 'dart:typed_data';
import 'package:animemaster/src/api/dio_client.dart';
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

void main() {
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

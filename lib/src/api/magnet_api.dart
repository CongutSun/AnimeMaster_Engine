import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../utils/torrent_cache_fetcher.dart';
import 'package:dio/dio.dart';

import '../config/embedded_credentials.dart';
import '../utils/task_title_parser.dart';
import '../models/rss_resource.dart';
import '../services/rss_feed_service.dart';
import '../services/public_search_cache.dart';
import 'dio_client.dart';

class MagnetApi {
  static final Dio _dio = DioClient().dio;

  static Future<List<Map<String, String>>> searchTorrents({
    required String keyword,
    required List<Map<String, String>> selectedSources,
    List<String> aliases = const [],
    RssFeedService? feedService,
    String mustInclude = '',
    String quality = '',
    String exclude = '',
    int? targetEpisodeNumber,
    void Function(List<Map<String, String>> results)? onResults,
    void Function(String source, bool succeeded)? onSourceComplete,
  }) async {
    final batches = List.generate(
      selectedSources.length,
      (_) => <Map<String, String>>[],
    );
    await Future.wait(
      selectedSources.indexed.map((entry) async {
        final (index, source) = entry;
        if (source['enabled'] == 'false') return;
        final key = jsonEncode([
          source['url'],
          source['name'],
          keyword,
          aliases,
          mustInclude,
          quality,
          exclude,
          targetEpisodeNumber,
        ]);
        final sourceKey = source['url'] ?? '';
        var success = false;
        try {
          if (_cooling(sourceKey)) throw StateError('来源稍后重试');
          batches[index] = await _fetchFromSource(
            source: source,
            keyword: keyword,
            mustInclude: mustInclude,
            quality: quality,
            exclude: exclude,
            targetEpisodeNumber: targetEpisodeNumber,
            aliases: aliases,
            feedService: feedService,
          );
          _failures.remove(sourceKey);
          _recent.remove(key);
          _recent[key] = (DateTime.now(), batches[index].take(150).toList());
          if (_recent.length > 40) _recent.remove(_recent.keys.first);
          if (PublicSearchCache.accepts(sourceKey)) {
            await PublicSearchCache.save(key, _recent[key]!.$1, batches[index]);
          }
          success = true;
        } catch (_) {
          if (!_cooling(sourceKey)) _failed(sourceKey);
          final old =
              _recent[key] ??
              (PublicSearchCache.accepts(sourceKey)
                  ? await PublicSearchCache.load(key)
                  : null);
          if (old != null &&
              DateTime.now().difference(old.$1) < const Duration(days: 1)) {
            batches[index] = [
              for (final item in old.$2)
                {
                  ...item,
                  'cachedAt': old.$1.toLocal().toString().split('.').first,
                },
            ];
          }
        }
        onResults?.call(groupResults(batches.expand((items) => items)));
        onSourceComplete?.call(source['name'] ?? '未知源', success);
      }),
    );
    return groupResults(batches.expand((items) => items));
  }

  static final _recent = <String, (DateTime, List<Map<String, String>>)>{};
  static final _failures = <String, (int, DateTime)>{};
  static bool _cooling(String key) {
    final last = _failures[key];
    return last != null &&
        last.$1 >= 2 &&
        DateTime.now().difference(last.$2) < const Duration(minutes: 2);
  }

  static void _failed(String key) {
    if (_failures.length >= 128 && !_failures.containsKey(key)) {
      _failures.remove(_failures.keys.first);
    }
    _failures[key] = ((_failures[key]?.$1 ?? 0) + 1, DateTime.now());
  }

  static List<String> routes(Map<String, String> item) => item['routes'] == null
      ? []
      : List<String>.from(jsonDecode(item['routes']!));
  static List<Map<String, String>> groupResults(
    Iterable<Map<String, String>> results,
  ) {
    final groups = <String, Map<String, String>>{};
    for (final item in results) {
      final magnetHash = TorrentCacheFetcher.canonicalHash(
        item['magnet'] ?? '',
      );
      final hash = magnetHash.isNotEmpty
          ? magnetHash
          : TorrentCacheFetcher.canonicalHash(item['torrent'] ?? '');
      final link = (item['torrent'] ?? '').isNotEmpty
          ? item['torrent']!
          : item['magnet'] ?? '';
      final key = hash.isNotEmpty
          ? hash
          : link.isNotEmpty
          ? link
          : jsonEncode([item['source'], item['title']]);
      final old = groups[key];
      final urls = {
        if (old != null) ...routes(old),
        if ((item['torrent'] ?? '').isNotEmpty) item['torrent']!,
        if ((item['magnet'] ?? '').isNotEmpty) item['magnet']!,
      };
      final names = {
        if (old != null) ...List<String>.from(jsonDecode(old['sources']!)),
        item['source'] ?? '未知源',
      };
      final first =
          old == null ||
              old.containsKey('cachedAt') && !item.containsKey('cachedAt')
          ? item
          : old;
      groups[key] = {
        ...first,
        'sources': jsonEncode(names.toList()),
        'source': names.join(' / '),
        'routes': jsonEncode(urls.toList()),
        'hash': hash,
        if ((first['torrent'] ?? '').isEmpty &&
            urls.any((u) => u.startsWith('https://')))
          'torrent': urls.firstWhere((u) => u.startsWith('https://')),
        if (hash.isNotEmpty && (first['magnet'] ?? '').isEmpty)
          'magnet': 'magnet:?xt=urn:btih:$hash',
      };
    }
    return groups.values.toList();
  }

  static Future<List<Map<String, String>>> _fetchFromSource({
    required Map<String, String> source,
    required String keyword,
    required String mustInclude,
    required String quality,
    required String exclude,
    required int? targetEpisodeNumber,
    required List<String> aliases,
    RssFeedService? feedService,
  }) async {
    final String rawUrl = source['url']?.trim() ?? '';
    if (rawUrl.isEmpty) {
      return <Map<String, String>>[];
    }
    if (source['enabled'] == 'false') return [];
    final isFixed = isSubscriptionSource(source);
    final publicSearch =
        rawUrl ==
            'https://share.dmhy.org/topics/rss/rss.xml?keyword={keyword}' ||
        rawUrl == 'https://mikanani.me/RSS/Search?searchstr={keyword}';
    final requestUrl = rawUrl.replaceAll(
      '{keyword}',
      Uri.encodeComponent(keyword),
    );
    final RssFeedSnapshot feed;
    if (publicSearch && feedService == null) {
      final bytes = await _requestFeedBytes(
        _buildCandidateFeedUrls(requestUrl),
      );
      if (bytes == null) throw StateError('搜索源暂不可用');
      feed = RssFeedService.parse(utf8.decode(bytes), Uri.parse(requestUrl));
    } else {
      feed = await (feedService ?? RssFeedService.instance).fetch(requestUrl);
    }
    return feed.items
        .where(
          (item) =>
              item.downloadUrl.isNotEmpty &&
              (!isFixed ||
                  RssFeedService.matchesTitle(item.title, [
                    keyword,
                    ...aliases,
                  ])) &&
              (mustInclude.isEmpty ||
                  item.title.toLowerCase().contains(
                    mustInclude.toLowerCase(),
                  )) &&
              (quality.isEmpty ||
                  item.title.toLowerCase().contains(quality.toLowerCase())) &&
              (exclude.isEmpty ||
                  !item.title.toLowerCase().contains(exclude.toLowerCase())) &&
              (targetEpisodeNumber == null ||
                  _coversEpisode(item.title, targetEpisodeNumber)),
        )
        .map(
          (item) => <String, String>{
            'title': '[${source['name']}] ${item.title}',
            'magnet': item.magnet,
            'torrent': item.torrent,
            'url': item.detailUrl,
            'date': item.publishedAt?.toIso8601String() ?? '',
            'source': source['name'] ?? '',
          },
        )
        .toList();
  }

  static bool _coversEpisode(String title, int n) {
    final range = TaskTitleParser.collectionRange(title);
    return range == null
        ? TaskTitleParser.matchesEpisodeNumber(title, n)
        : n >= range.$1 && n <= range.$2;
  }

  static bool sourceCoolingDown(String url) => _cooling(url);

  static List<String> _buildCandidateFeedUrls(String requestUrl) {
    final Uri? uri = Uri.tryParse(requestUrl);
    final String host = uri?.host.toLowerCase() ?? '';
    final List<String> candidates = <String>[requestUrl];

    if (host.contains('share.dmhy.org')) {
      candidates.add(_proxyUrl('rss', requestUrl));
      candidates.add(
        'https://api.codetabs.com/v1/proxy?quest=${Uri.encodeComponent(requestUrl)}',
      );
      candidates.add(
        'https://api.allorigins.win/raw?url=${Uri.encodeComponent(requestUrl)}',
      );
    } else if (host.contains('mikanani.me')) {
      final String mirrorUrl = requestUrl.replaceAll(
        'mikanani.me',
        'mikanime.tv',
      );
      candidates.add(mirrorUrl);
      candidates.add(_proxyUrl('rss', requestUrl));
      candidates.add(_proxyUrl('rss', mirrorUrl));
      candidates.add(
        'https://api.allorigins.win/raw?url=${Uri.encodeComponent(requestUrl)}',
      );
    } else if (host.contains('mikanime.tv')) {
      final String mirrorUrl = requestUrl.replaceAll(
        'mikanime.tv',
        'mikanani.me',
      );
      candidates.add(mirrorUrl);
      candidates.add(_proxyUrl('rss', requestUrl));
      candidates.add(_proxyUrl('rss', mirrorUrl));
      candidates.add(
        'https://api.allorigins.win/raw?url=${Uri.encodeComponent(requestUrl)}',
      );
    }

    return candidates.toSet().toList();
  }

  static Future<Uint8List?> _requestFeedBytes(
    List<String> candidateUrls,
  ) async {
    if (candidateUrls.isEmpty) {
      return null;
    }

    final available = candidateUrls
        .where((url) => !_cooling(Uri.parse(url).host))
        .toList();
    if (available.isEmpty) return null;
    final cancel = CancelToken();
    final Completer<Uint8List?> completer = Completer<Uint8List?>();
    int pending = available.length;
    bool resolved = false;

    final Timer globalTimeout = Timer(const Duration(seconds: 20), () {
      if (!resolved) {
        resolved = true;
        completer.complete(null);
      }
    });

    for (final String url in available) {
      unawaited(
        _downloadFeedBytes(url, cancel).then((Uint8List? bytes) {
          if (!resolved) {
            if (bytes == null) {
              _failed(Uri.parse(url).host);
            } else {
              _failures.remove(Uri.parse(url).host);
            }
          }
          if (bytes != null && bytes.isNotEmpty && !resolved) {
            resolved = true;
            globalTimeout.cancel();
            completer.complete(bytes);
            return;
          }

          pending--;
          if (pending == 0 && !resolved) {
            resolved = true;
            globalTimeout.cancel();
            completer.complete(null);
          }
        }),
      );
    }

    return completer.future.whenComplete(() {
      globalTimeout.cancel();
      cancel.cancel();
    });
  }

  static Future<Uint8List?> _downloadFeedBytes(
    String url,
    CancelToken cancel,
  ) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        url,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode != 200) {
        return null;
      }

      final dynamic data = response.data;
      // Do not let a proxy's HTML error page win the request race.
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in (data as ResponseBody).stream) {
        if (buffer.length + chunk.length > RssFeedService.maxBytes) return null;
        buffer.add(chunk);
      }
      final bytes = buffer.takeBytes();
      final xml = utf8.decode(bytes);
      if (!xml.contains('<rss') && !xml.contains('<feed')) return null;
      RssFeedService.parse(xml, Uri.parse(url));
      return bytes;
    } catch (_) {}

    return null;
  }

  static String _proxyUrl(String mode, String targetUrl) {
    final String baseUrl = EmbeddedCredentials.resourceProxyBaseUrl.trim();
    if (baseUrl.isEmpty) {
      return targetUrl;
    }
    return '${baseUrl.replaceFirst(RegExp(r'/$'), '')}/proxy/$mode?url=${Uri.encodeComponent(targetUrl)}';
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:dart_rss/dart_rss.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/embedded_credentials.dart';
import '../utils/task_title_parser.dart';
import '../models/rss_resource.dart';
import '../services/rss_feed_service.dart';
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
    final partial = <String, Map<String, String>>{};
    final Iterable<Future<List<Map<String, String>>>> futures = selectedSources
        .map((Map<String, String> source) async {
          try {
            final items = await _fetchFromSource(
              source: source,
              keyword: keyword,
              mustInclude: mustInclude,
              quality: quality,
              exclude: exclude,
              targetEpisodeNumber: targetEpisodeNumber,
              aliases: aliases,
              feedService: feedService,
            );
            for (final item in items) {
              partial[_resultKey(item)] = item;
            }
            onResults?.call(partial.values.toList());
            onSourceComplete?.call(source['name'] ?? '未知源', true);
            return items;
          } catch (_) {
            onSourceComplete?.call(source['name'] ?? '未知源', false);
            return <Map<String, String>>[];
          }
        });

    final List<List<Map<String, String>>> results = await Future.wait(futures);
    final Map<String, Map<String, String>> deduplicated =
        <String, Map<String, String>>{};

    for (final List<Map<String, String>> sourceResults in results) {
      for (final Map<String, String> item in sourceResults) {
        final String key = _resultKey(item);
        deduplicated[key] = item;
      }
    }

    return deduplicated.values.toList();
  }

  static String _resultKey(Map<String, String> item) =>
      item['torrent']?.trim().isNotEmpty == true
      ? item['torrent']!.trim()
      : (item['magnet']?.trim().isNotEmpty == true
            ? item['magnet']!.trim()
            : '${item['source']}|${item['title']}');

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
    if (isFixed || !publicSearch) {
      final feed = await (feedService ?? RssFeedService.instance).fetch(
        rawUrl.replaceAll('{keyword}', Uri.encodeComponent(keyword)),
      );
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
                    !item.title.toLowerCase().contains(
                      exclude.toLowerCase(),
                    )) &&
                (targetEpisodeNumber == null ||
                    TaskTitleParser.matchesEpisodeNumber(
                      item.title,
                      targetEpisodeNumber,
                    )),
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

    final String requestUrl = rawUrl.replaceAll(
      '{keyword}',
      Uri.encodeComponent(keyword),
    );
    final List<String> candidateUrls = _buildCandidateFeedUrls(requestUrl);

    try {
      final Uint8List? feedBytes = await _requestFeedBytes(candidateUrls);
      if (feedBytes == null || feedBytes.isEmpty) {
        throw StateError('搜索源暂不可用');
      }

      final RssFeed feed = RssFeed.parse(utf8.decode(feedBytes));
      final String mustIncludeLower = mustInclude.trim().toLowerCase();
      final String qualityLower = quality.trim().toLowerCase();
      final String excludeLower = exclude.trim().toLowerCase();
      final List<Map<String, String>> results = <Map<String, String>>[];

      for (final RssItem item in feed.items) {
        final String rawTitle = item.title?.trim() ?? '未知资源';
        final String titleLower = rawTitle.toLowerCase();

        if (mustIncludeLower.isNotEmpty &&
            !titleLower.contains(mustIncludeLower)) {
          continue;
        }
        if (qualityLower.isNotEmpty && !titleLower.contains(qualityLower)) {
          continue;
        }
        if (excludeLower.isNotEmpty && titleLower.contains(excludeLower)) {
          continue;
        }
        if (targetEpisodeNumber != null &&
            targetEpisodeNumber > 0 &&
            !TaskTitleParser.matchesEpisodeNumber(
              rawTitle,
              targetEpisodeNumber,
            )) {
          continue;
        }

        final String enclosureUrl = item.enclosure?.url?.trim() ?? '';
        final String linkUrl = item.link?.trim() ?? '';

        String magnet = '';
        String torrentUrl = '';

        if (_isMagnetLink(enclosureUrl)) {
          magnet = enclosureUrl;
        } else if (_isMagnetLink(linkUrl)) {
          magnet = linkUrl;
        }

        if (_looksLikeTorrentUrl(enclosureUrl)) {
          torrentUrl = enclosureUrl;
        } else if (_looksLikeTorrentUrl(linkUrl)) {
          torrentUrl = linkUrl;
        }

        if (magnet.isEmpty) {
          final String hashSource = torrentUrl.isNotEmpty
              ? torrentUrl
              : linkUrl;
          final Match? hashMatch = RegExp(
            r'([a-zA-Z0-9]{32,40})\.torrent',
            caseSensitive: false,
          ).firstMatch(hashSource);
          if (hashMatch != null) {
            magnet = 'magnet:?xt=urn:btih:${hashMatch.group(1)!.toUpperCase()}';
          }
        }

        if (magnet.isEmpty && torrentUrl.isEmpty) {
          continue;
        }

        results.add(<String, String>{
          'title': '[${source['name'] ?? '未知源'}] $rawTitle',
          'magnet': magnet,
          'torrent': torrentUrl,
          'url': linkUrl,
          'date': item.pubDate?.toString() ?? '未知时间',
          'source': source['name'] ?? '未知源',
        });
      }

      return results;
    } catch (error) {
      debugPrint(
        '[MagnetApi] Fetch failed for source ${source['name']}: $error',
      );
      rethrow;
    }
  }

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

    final Completer<Uint8List?> completer = Completer<Uint8List?>();
    int pending = candidateUrls.length;
    bool resolved = false;

    final Timer globalTimeout = Timer(const Duration(seconds: 20), () {
      if (!resolved) {
        resolved = true;
        completer.complete(null);
      }
    });

    for (final String url in candidateUrls) {
      unawaited(
        _downloadFeedBytes(url).then((Uint8List? bytes) {
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

    return completer.future;
  }

  static Future<Uint8List?> _downloadFeedBytes(String url) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode != 200) {
        return null;
      }

      final dynamic data = response.data;
      // Do not let a proxy's HTML error page win the request race.
      final bytes = Uint8List.fromList(List<int>.from(data as List));
      final xml = utf8.decode(bytes);
      if (!xml.contains('<rss') && !xml.contains('<feed')) return null;
      RssFeed.parse(xml);
      return bytes;
    } catch (_) {}

    return null;
  }

  static bool _isMagnetLink(String value) {
    return value.toLowerCase().startsWith('magnet:');
  }

  static String _proxyUrl(String mode, String targetUrl) {
    final String baseUrl = EmbeddedCredentials.resourceProxyBaseUrl.trim();
    if (baseUrl.isEmpty) {
      return targetUrl;
    }
    return '${baseUrl.replaceFirst(RegExp(r'/$'), '')}/proxy/$mode?url=${Uri.encodeComponent(targetUrl)}';
  }

  static bool _looksLikeTorrentUrl(String value) {
    final String lower = value.toLowerCase();
    return lower.startsWith('http') &&
        (lower.contains('.torrent') ||
            lower.contains('/download') ||
            lower.contains('/dl/'));
  }
}
